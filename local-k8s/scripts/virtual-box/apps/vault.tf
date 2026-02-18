# HashiCorp Vault - Secret Management (persistent storage)
resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = "vault"
  create_namespace = true
  version          = "0.28.1"

  values = [<<-YAML
    server:
      standalone:
        enabled: true
        config: |
          ui = true
          listener "tcp" {
            tls_disable = 1
            address = "[::]:8200"
            cluster_address = "[::]:8201"
          }
          storage "file" {
            path = "/vault/data"
          }
      dataStorage:
        enabled: true
        size: 1Gi
        storageClass: nfs-client
      resources:
        requests:
          memory: 128Mi
          cpu: 100m
        limits:
          memory: 256Mi
          cpu: 500m
      volumes:
        - name: vault-unseal
          secret:
            secretName: vault-unseal-key
            optional: true
      volumeMounts:
        - name: vault-unseal
          mountPath: /vault/unseal
          readOnly: true
      postStart:
        - /bin/sh
        - -c
        - |
          sleep 10
          if [ -f /vault/unseal/key ]; then
            vault operator unseal $(cat /vault/unseal/key) 2>/dev/null || true
          fi
    ui:
      enabled: true
    injector:
      enabled: false
  YAML
  ]

  # Vault won't be Ready until unsealed, so don't wait
  wait = false

  depends_on = [
    helm_release.nginx_ingress,
    helm_release.nfs_provisioner
  ]
}

# Ingress for Vault UI
resource "kubernetes_ingress_v1" "vault" {
  metadata {
    name      = "vault-ingress"
    namespace = "vault"
    annotations = {
      "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
      "nginx.ingress.kubernetes.io/ssl-redirect"        = "false"
      "nginx.ingress.kubernetes.io/force-ssl-redirect"  = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "vault.${local.haproxy_ip}.nip.io"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "vault"
              port {
                number = 8200
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.vault]
}

# External Secrets Operator - syncs secrets from Vault to Kubernetes
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.10.7"

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "250m"
  }

  wait = true

  depends_on = [
    helm_release.vault
  ]
}

# Initialize, unseal, and configure Vault
resource "null_resource" "vault_init" {
  depends_on = [helm_release.vault]

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command = <<-EOT
      $KUBECONFIG = "${pathexpand("~/.kube/config-virtualbox")}"

      Write-Host "Waiting for Vault pod to be running..."
      for ($i = 1; $i -le 60; $i++) {
        $POD_STATUS = kubectl --kubeconfig $KUBECONFIG -n vault get pod vault-0 -o jsonpath='{.status.phase}' 2>$null
        if ($POD_STATUS -eq "Running") { break }
        Start-Sleep -Seconds 2
      }
      Start-Sleep -Seconds 10

      # Check if already initialized
      try {
        $statusJson = kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault status -format=json 2>$null
        $INIT_STATUS = ($statusJson | ConvertFrom-Json).initialized
      } catch {
        $INIT_STATUS = $false
      }

      if (-not $INIT_STATUS) {
        Write-Host "Initializing Vault..."
        $INIT_OUTPUT = kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json
        $initData = $INIT_OUTPUT | ConvertFrom-Json

        $UNSEAL_KEY = $initData.unseal_keys_b64[0]
        $ROOT_TOKEN = $initData.root_token

        Write-Host "Unsealing Vault..."
        kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault operator unseal $UNSEAL_KEY

        Write-Host "Storing unseal key and root token as K8s secret..."
        kubectl --kubeconfig $KUBECONFIG -n vault create secret generic vault-unseal-key `
          --from-literal=key="$UNSEAL_KEY" `
          --from-literal=root-token="$ROOT_TOKEN" `
          --dry-run=client -o yaml | kubectl --kubeconfig $KUBECONFIG apply -f -

        Write-Host "Creating vault-token secret for ESO..."
        kubectl --kubeconfig $KUBECONFIG -n vault create secret generic vault-token `
          --from-literal=token="$ROOT_TOKEN" `
          --dry-run=client -o yaml | kubectl --kubeconfig $KUBECONFIG apply -f -

        Write-Host "Enabling KV v2 secrets engine..."
        Start-Sleep -Seconds 5
        kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets enable -path=secret kv-v2"

        Write-Host "Vault initialized and configured successfully"
      } else {
        Write-Host "Vault is already initialized"

        # Unseal if needed
        try {
          $statusJson = kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault status -format=json 2>$null
          $SEALED = ($statusJson | ConvertFrom-Json).sealed
        } catch {
          $SEALED = $true
        }

        if ($SEALED) {
          Write-Host "Unsealing Vault..."
          $UNSEAL_KEY = kubectl --kubeconfig $KUBECONFIG -n vault get secret vault-unseal-key -o jsonpath='{.data.key}'
          $UNSEAL_KEY = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($UNSEAL_KEY))
          kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault operator unseal $UNSEAL_KEY
        }

        # Ensure vault-token secret exists for ESO
        $ROOT_TOKEN = kubectl --kubeconfig $KUBECONFIG -n vault get secret vault-unseal-key -o jsonpath='{.data.root-token}'
        $ROOT_TOKEN = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ROOT_TOKEN))
        kubectl --kubeconfig $KUBECONFIG -n vault create secret generic vault-token `
          --from-literal=token="$ROOT_TOKEN" `
          --dry-run=client -o yaml | kubectl --kubeconfig $KUBECONFIG apply -f -
      }
    EOT
  }
}

# ClusterSecretStore - connects ESO to Vault (applied via kubectl)
resource "null_resource" "vault_cluster_secret_store" {
  depends_on = [
    helm_release.external_secrets,
    null_resource.vault_init
  ]

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command = <<-EOT
      @"
      apiVersion: external-secrets.io/v1beta1
      kind: ClusterSecretStore
      metadata:
        name: vault-backend
      spec:
        provider:
          vault:
            server: "http://vault.vault.svc.cluster.local:8200"
            path: "secret"
            version: "v2"
            auth:
              tokenSecretRef:
                name: "vault-token"
                namespace: "vault"
                key: "token"
      "@ | kubectl --kubeconfig "${pathexpand("~/.kube/config-virtualbox")}" apply -f -
    EOT
  }
}

# Output Vault URL
output "vault_url" {
  value       = "http://vault.${local.haproxy_ip}.nip.io"
  description = "Vault UI URL"
}

output "vault_root_token_command" {
  value       = "kubectl -n vault get secret vault-unseal-key -o jsonpath='{.data.root-token}' | base64 -d"
  description = "Command to retrieve Vault root token"
}

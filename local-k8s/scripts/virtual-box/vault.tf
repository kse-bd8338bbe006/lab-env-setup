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
    interpreter = ["bash", "-c"]
    command = <<-EOT
      KUBECONFIG="$HOME/.kube/config-virtualbox"

      echo "Waiting for Vault pod to be running..."
      for i in $(seq 1 60); do
        POD_STATUS=$(kubectl --kubeconfig $KUBECONFIG -n vault get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$POD_STATUS" = "Running" ]; then
          break
        fi
        sleep 2
      done
      sleep 10

      # Check if already initialized
      INIT_STATUS=$(kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault status -format=json 2>/dev/null \
        | python -c "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")

      if [ "$INIT_STATUS" = "False" ] || [ "$INIT_STATUS" = "false" ]; then
        echo "Initializing Vault..."
        INIT_OUTPUT=$(kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json)

        UNSEAL_KEY=$(echo "$INIT_OUTPUT" | python -c "import sys,json; print(json.load(sys.stdin)['unseal_keys_b64'][0])")
        ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python -c "import sys,json; print(json.load(sys.stdin)['root_token'])")

        echo "Unsealing Vault..."
        kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault operator unseal "$UNSEAL_KEY"

        echo "Storing unseal key and root token as K8s secret..."
        kubectl --kubeconfig $KUBECONFIG -n vault create secret generic vault-unseal-key \
          --from-literal=key="$UNSEAL_KEY" \
          --from-literal=root-token="$ROOT_TOKEN" \
          --dry-run=client -o yaml | kubectl --kubeconfig $KUBECONFIG apply -f -

        echo "Creating vault-token secret for ESO..."
        kubectl --kubeconfig $KUBECONFIG -n vault create secret generic vault-token \
          --from-literal=token="$ROOT_TOKEN" \
          --dry-run=client -o yaml | kubectl --kubeconfig $KUBECONFIG apply -f -

        echo "Enabling KV v2 secrets engine..."
        sleep 5
        kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets enable -path=secret kv-v2"

        echo "Vault initialized and configured successfully"
      else
        echo "Vault is already initialized"

        # Unseal if needed
        SEALED=$(kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault status -format=json 2>/dev/null \
          | python -c "import sys,json; print(json.load(sys.stdin)['sealed'])" 2>/dev/null || echo "true")

        if [ "$SEALED" = "True" ] || [ "$SEALED" = "true" ]; then
          echo "Unsealing Vault..."
          UNSEAL_KEY=$(kubectl --kubeconfig $KUBECONFIG -n vault get secret vault-unseal-key -o jsonpath='{.data.key}' | base64 -d)
          kubectl --kubeconfig $KUBECONFIG -n vault exec vault-0 -- vault operator unseal "$UNSEAL_KEY"
        fi

        # Ensure vault-token secret exists for ESO
        ROOT_TOKEN=$(kubectl --kubeconfig $KUBECONFIG -n vault get secret vault-unseal-key -o jsonpath='{.data.root-token}' | base64 -d)
        kubectl --kubeconfig $KUBECONFIG -n vault create secret generic vault-token \
          --from-literal=token="$ROOT_TOKEN" \
          --dry-run=client -o yaml | kubectl --kubeconfig $KUBECONFIG apply -f -
      fi
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
    interpreter = ["bash", "-c"]
    command = <<-EOT
      kubectl --kubeconfig "$HOME/.kube/config-virtualbox" apply -f - <<'EOF'
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
      EOF
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

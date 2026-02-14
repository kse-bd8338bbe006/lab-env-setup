resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.10"

  # Disable TLS on server (Ingress handles TLS termination or we use HTTP)
  set {
    name  = "server.insecure"
    value = "true"
  }

  # Disable HTTPS redirect in ArgoCD server
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  # Wait for the release to be deployed
  wait = true

  depends_on = [
    helm_release.nginx_ingress
  ]
}

# Create Ingress for ArgoCD
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      "nginx.ingress.kubernetes.io/backend-protocol"  = "HTTP"
      "nginx.ingress.kubernetes.io/ssl-redirect"      = "false"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "argocd.${local.haproxy_ip}.nip.io"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}

# Output ArgoCD initial admin password retrieval command
output "argocd_initial_password_command" {
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  description = "Command to retrieve ArgoCD initial admin password"
}

output "argocd_url" {
  value       = "http://argocd.${local.haproxy_ip}.nip.io"
  description = "ArgoCD URL"
}

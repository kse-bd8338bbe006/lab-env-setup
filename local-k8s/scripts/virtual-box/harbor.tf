# Generate random password for Harbor admin
resource "random_password" "harbor_admin" {
  length           = 16
  special          = true
  override_special = "!@#$%"
}

# Harbor Container Registry Installation
resource "helm_release" "harbor" {
  name             = "harbor"
  repository       = "https://helm.goharbor.io"
  chart            = "harbor"
  namespace        = "harbor"
  version          = "1.18.1"
  create_namespace = true

  values = [
    yamlencode({
      # External URL for Harbor
      externalURL = "http://harbor.${local.haproxy_ip}.nip.io"

      # Expose Harbor via Ingress
      expose = {
        type = "ingress"
        tls = {
          enabled = false
        }
        ingress = {
          hosts = {
            core = "harbor.${local.haproxy_ip}.nip.io"
          }
          className = "nginx"
          annotations = {
            "nginx.ingress.kubernetes.io/ssl-redirect"       = "false"
            "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
            "nginx.ingress.kubernetes.io/proxy-body-size"    = "0"
          }
        }
      }

      # Disable internal TLS between components
      internalTLS = {
        enabled = false
      }

      # Harbor admin password (randomly generated)
      harborAdminPassword = random_password.harbor_admin.result

      # Persistence configuration using NFS StorageClass
      persistence = {
        enabled = true
        resourcePolicy = "keep"
        persistentVolumeClaim = {
          registry = {
            storageClass = "nfs-client"
            size         = "10Gi"
          }
          jobservice = {
            jobLog = {
              storageClass = "nfs-client"
              size         = "1Gi"
            }
          }
          database = {
            storageClass = "nfs-client"
            size         = "2Gi"
          }
          redis = {
            storageClass = "nfs-client"
            size         = "1Gi"
          }
          trivy = {
            storageClass = "nfs-client"
            size         = "5Gi"
          }
        }
      }

      # Use internal database (PostgreSQL)
      database = {
        type = "internal"
      }

      # Use internal Redis
      redis = {
        type = "internal"
      }

      # Trivy vulnerability scanner
      trivy = {
        enabled = true
      }

      # Resource limits for components
      portal = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      core = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "300m"
            memory = "512Mi"
          }
        }
      }

      registry = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "300m"
            memory = "512Mi"
          }
        }
      }

      jobservice = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "512Mi"
          }
        }
      }
    })
  ]

  wait    = true
  timeout = 600

  depends_on = [
    helm_release.nfs_provisioner,
    helm_release.nginx_ingress
  ]
}

output "harbor_url" {
  value       = "http://harbor.${local.haproxy_ip}.nip.io"
  description = "Harbor URL"
}

output "harbor_admin_password" {
  value       = random_password.harbor_admin.result
  sensitive   = true
  description = "Harbor admin password (use: terraform output -raw harbor_admin_password)"
}

output "harbor_credentials" {
  value       = "admin / (run: terraform output -raw harbor_admin_password)"
  description = "Harbor admin credentials"
}

output "harbor_docker_login" {
  value       = "docker login harbor.${local.haproxy_ip}.nip.io -u admin -p $(terraform output -raw harbor_admin_password)"
  description = "Docker login command for Harbor"
}

# # Generate random password for Dependency-Track admin
# resource "random_password" "dependencytrack_admin" {
#   length           = 16
#   special          = true
#   override_special = "!@#$%"
# }

# # Dependency-Track Installation
# resource "helm_release" "dependency_track" {
#   name             = "dependency-track"
#   repository       = "https://dependencytrack.github.io/helm-charts"
#   chart            = "dependency-track"
#   namespace        = "dependency-track"
#   version          = "0.41.0"
#   create_namespace = true

#   values = [
#     yamlencode({
#       # API Server configuration
#       apiServer = {
#         resources = {
#           requests = {
#             cpu    = "500m"
#             memory = "1.7Gi"
#           }
#           limits = {
#             cpu    = "2"
#             memory = "5Gi"  # the recommended minimum
#           }
#         }

#         persistentVolume = {
#           enabled = true
#           size    = "5Gi"
#           storageClass = "nfs-client"
#         }
#       }

#       # Frontend configuration
#       frontend = {
#         resources = {
#           requests = {
#             cpu    = "100m"
#             memory = "64Mi"
#           }
#           limits = {
#             cpu    = "500m"
#             memory = "128Mi"
#           }
#         }
#       }

#       # Ingress configuration
#       ingress = {
#         enabled = true
#         annotations = {
#           "nginx.ingress.kubernetes.io/ssl-redirect"       = "false"
#           "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
#           "nginx.ingress.kubernetes.io/proxy-body-size"    = "10m"
#         }
#         hostname = "dtrack.${local.haproxy_ip}.nip.io"
#         ingressClassName = "nginx"
#       }
#     })
#   ]

#   wait    = true
#   timeout = 900  # Dependency-Track takes a while to start

#   depends_on = [
#     helm_release.nfs_provisioner,
#     helm_release.nginx_ingress
#   ]
# }

# output "dependency_track_url" {
#   value       = "http://dtrack.${local.haproxy_ip}.nip.io"
#   description = "Dependency-Track URL"
# }

# output "dependency_track_credentials" {
#   value       = "admin / admin (change on first login)"
#   description = "Dependency-Track default admin credentials"
# }

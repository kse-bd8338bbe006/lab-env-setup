# NFS Subdir External Provisioner
resource "helm_release" "nfs_provisioner" {
  name             = "nfs-subdir-external-provisioner"
  repository       = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner"
  chart            = "nfs-subdir-external-provisioner"
  namespace        = "nfs-provisioner"
  create_namespace = true
  version          = "4.0.18"

  set {
    name  = "nfs.server"
    value = local.haproxy_ip
  }

  set {
    name  = "nfs.path"
    value = "/srv/nfs/k8s-storage"
  }

  set {
    name  = "storageClass.defaultClass"
    value = "true"
  }

  set {
    name  = "storageClass.name"
    value = "nfs-client"
  }

  set {
    name  = "storageClass.reclaimPolicy"
    value = "Delete"
  }

  wait = true

  depends_on = [
    helm_release.nginx_ingress
  ]
}

output "storage_class_name" {
  value       = "nfs-client"
  description = "Default StorageClass name for PVCs"
}

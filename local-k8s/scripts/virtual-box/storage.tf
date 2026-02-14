# Install NFS server on HAProxy VM
resource "null_resource" "nfs_server" {
  depends_on = [null_resource.haproxy]

  connection {
    type        = "ssh"
    host        = local.haproxy_ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "remote-exec" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update",
      "apt-get install -y nfs-kernel-server",
      "mkdir -p /srv/nfs/k8s-storage",
      "chown nobody:nogroup /srv/nfs/k8s-storage",
      "chmod 777 /srv/nfs/k8s-storage",
      "echo '/srv/nfs/k8s-storage *(rw,sync,no_subtree_check,no_root_squash)' > /etc/exports",
      "exportfs -ra",
      "systemctl enable nfs-kernel-server",
      "systemctl restart nfs-kernel-server"
    ]
  }
}

# Install PostgreSQL on HAProxy VM
resource "null_resource" "postgresql" {
  depends_on = [null_resource.nfs_server]

  connection {
    type        = "ssh"
    host        = local.haproxy_ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib",
      "PG_CONF=$(find /etc/postgresql -name postgresql.conf | head -1)",
      "PG_HBA=$(find /etc/postgresql -name pg_hba.conf | head -1)",
      "sed -i \"s/#listen_addresses = 'localhost'/listen_addresses = '*'/\" $PG_CONF",
      "echo 'host all all 0.0.0.0/0 md5' >> $PG_HBA",
      "PG_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)",
      "sudo -u postgres psql -c \"ALTER USER postgres PASSWORD '$PG_PASSWORD';\"",
      "echo \"PostgreSQL password: $PG_PASSWORD\" > /root/postgres_credentials.txt",
      "chmod 600 /root/postgres_credentials.txt",
      "systemctl enable postgresql",
      "systemctl restart postgresql"
    ]
  }
}

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
    null_resource.nfs_server,
    helm_release.nginx_ingress
  ]
}

output "storage_class_name" {
  value       = "nfs-client"
  description = "Default StorageClass name for PVCs"
}

output "postgresql_host" {
  value       = local.haproxy_ip
  description = "PostgreSQL host IP"
}

output "postgresql_credentials_command" {
  value       = "multipass exec haproxy -- cat /root/postgres_credentials.txt"
  description = "Command to retrieve PostgreSQL password"
}

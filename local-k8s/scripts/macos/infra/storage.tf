# Install NFS server on HAProxy VM
resource "null_resource" "nfs_server" {
  depends_on = [null_resource.haproxy]

  connection {
    type        = "ssh"
    host        = data.external.haproxy.result.ip
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
    host        = data.external.haproxy.result.ip
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

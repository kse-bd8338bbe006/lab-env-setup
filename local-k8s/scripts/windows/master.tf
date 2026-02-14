resource "null_resource" "master-node" {
  depends_on = [null_resource.haproxy]

  triggers = {
    id = local.master_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = local.master_ips[count.index]
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "remote-exec" {
    script = "${path.module}/script/kube-init.sh"
  }

  provisioner "local-exec" {
    command     = "echo ${local.master_ips[count.index]} master-${count.index} >> $env:TEMP\\hosts_ip.txt"
    interpreter = ["pwsh", "-Command"]
  }
  count = 1
}

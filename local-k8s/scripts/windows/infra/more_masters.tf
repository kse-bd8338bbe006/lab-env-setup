resource "null_resource" "masters-node" {
  depends_on = [null_resource.workers-node]

  triggers = {
    id = local.master_ips[count.index + 1]
  }

  connection {
    type        = "ssh"
    host        = local.master_ips[count.index + 1]
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /tmp/signal ]; do sleep 2; done"
    ]
  }

  provisioner "local-exec" {
    command     = "echo ${local.master_ips[count.index + 1]} master-${count.index + 1} >> $env:TEMP\\hosts_ip.txt"
    interpreter = ["pwsh", "-Command"]
  }
  count = var.masters == 3 ? var.masters - 1 : 0
}

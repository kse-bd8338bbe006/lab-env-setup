resource "null_resource" "workers-node" {
  depends_on = [null_resource.master-node]

  triggers = {
    id = local.worker_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = local.worker_ips[count.index]
    user        = "root"
    private_key = file(local.ssh_private_key)
  }
  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /tmp/signal ]; do sleep 2; done"
    ]
  }
  provisioner "local-exec" {
    command     = "echo ${local.worker_ips[count.index]} worker-${count.index} >> $env:TEMP\\hosts_ip.txt"
    interpreter = ["pwsh", "-Command"]
  }
  count = var.workers >= 1 ? var.workers : 0
}

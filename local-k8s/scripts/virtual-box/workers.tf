# Worker nodes are created and joined by Vagrant
# This resource verifies workers are ready
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

  # Wait for kubelet to be running (indicates node joined cluster)
  provisioner "remote-exec" {
    inline = [
      "while ! systemctl is-active --quiet kubelet; do echo 'Waiting for kubelet...'; sleep 5; done"
    ]
  }

  provisioner "local-exec" {
    command     = "echo ${local.worker_ips[count.index]} worker-${count.index} >> $env:TEMP\\hosts_ip.txt"
    interpreter = ["pwsh", "-Command"]
  }
  count = var.workers >= 1 ? var.workers : 0
}

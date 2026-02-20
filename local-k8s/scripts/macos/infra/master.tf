resource "null_resource" "master-node" {
  depends_on = [null_resource.haproxy]

  triggers = {
    id = local.master_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = data.external.master[count.index].result.ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "remote-exec" {
    script = "${path.module}/../script/kube-init.sh"
  }

  provisioner "local-exec" {
    command = "echo ${local.master_ips[count.index]} master-${count.index} >> /tmp/hosts_ip.txt"
  }
  count = 1
}

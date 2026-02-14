resource "null_resource" "kube_config" {
  depends_on = [null_resource.master-node]
  provisioner "local-exec" {
    command = <<CMD
mkdir -p ${pathexpand("~/.kube")}
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${local.ssh_private_key} root@${data.external.master[0].result.ip}:/etc/kubernetes/admin.conf ${pathexpand("~/.kube/config-multipass")}
CMD
  }
}

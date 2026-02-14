# Master node is created and initialized by Vagrant
# This resource creates join files for workers
resource "null_resource" "master-node" {
  depends_on = [null_resource.wait_for_k8s]

  triggers = {
    id = local.master_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = local.master_ips[count.index]
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  # Generate join files if they don't exist
  provisioner "remote-exec" {
    inline = [
      "if [ ! -f /etc/join.json ]; then",
      "  echo -n '{\"join\":\"'$(kubeadm token create --ttl 0 --print-join-command)'\"}' > /etc/join.json",
      "fi",
      "if [ ! -f /etc/join-master.json ]; then",
      "  CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>&1 | tail -1)",
      "  echo -n '{\"join\":\"'$(kubeadm token create --ttl 0 --print-join-command)' --control-plane --certificate-key '$CERT_KEY'\"}' > /etc/join-master.json",
      "fi"
    ]
  }

  provisioner "local-exec" {
    command     = "echo ${local.master_ips[count.index]} master-${count.index} >> $env:TEMP\\hosts_ip.txt"
    interpreter = ["pwsh", "-Command"]
  }
  count = 1
}

# HAProxy VM is created by Vagrant
# This resource updates HAProxy config with proper backends
resource "null_resource" "haproxy" {

  triggers = {
    id = local.haproxy_ip
  }

  connection {
    type        = "ssh"
    host        = local.haproxy_ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  # Wait for HAProxy to be installed by Vagrant
  provisioner "remote-exec" {
    inline = [
      "while ! systemctl is-active --quiet haproxy; do echo 'Waiting for HAProxy...'; sleep 5; done"
    ]
  }

  provisioner "file" {
    source      = local_file.haproxy_initial_cfg.filename
    destination = "/etc/haproxy/haproxy.cfg"
  }

  provisioner "remote-exec" {
    inline = [
      "systemctl restart haproxy"
    ]
  }

  provisioner "local-exec" {
    command     = "echo ${local.haproxy_ip} haproxy >> $env:TEMP\\hosts_ip.txt"
    interpreter = ["pwsh", "-Command"]
  }
}

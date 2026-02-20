resource "null_resource" "haproxy" {

  triggers = {
    id = local.haproxy_ip
  }

  connection {
    type        = "ssh"
    host        = data.external.haproxy.result.ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /tmp/signal ]; do sleep 2; done"
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
    command = "echo ${local.haproxy_ip} haproxy >> /tmp/hosts_ip.txt"
  }
}

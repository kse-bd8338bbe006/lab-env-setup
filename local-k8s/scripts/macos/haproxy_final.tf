resource "null_resource" "haproxy_final" {
  depends_on = [null_resource.masters-node]

  connection {
    type        = "ssh"
    host        = data.external.haproxy.result.ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "file" {
    source      = local_file.haproxy_final_cfg[0].filename
    destination = "/etc/haproxy/haproxy.cfg"
  }

  provisioner "remote-exec" {
    inline = [
      "systemctl restart haproxy"
    ]
  }

  count = var.masters == 3 ? 1 : 0
}

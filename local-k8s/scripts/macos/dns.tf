resource "null_resource" "haproxy-dns" {
  depends_on = [null_resource.workers-node]

  connection {
    type        = "ssh"
    host        = data.external.haproxy.result.ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "file" {
    source      = "/tmp/hosts_ip.txt"
    destination = "/tmp/hosts_ip.txt"
  }

  provisioner "remote-exec" {
    inline = [
      "cat /tmp/hosts_ip.txt >> /etc/hosts",
    ]
  }
}

resource "null_resource" "master-dns" {
  depends_on = [null_resource.workers-node]

  connection {
    type        = "ssh"
    host        = data.external.master[count.index].result.ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "file" {
    source      = "/tmp/hosts_ip.txt"
    destination = "/tmp/hosts_ip.txt"
  }

  provisioner "remote-exec" {
    inline = [
      "cat /tmp/hosts_ip.txt >> /etc/hosts",
    ]
  }
  count = 1
}

resource "null_resource" "masters-dns" {
  depends_on = [null_resource.workers-node]

  connection {
    type        = "ssh"
    host        = data.external.masters[count.index].result.ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "file" {
    source      = "/tmp/hosts_ip.txt"
    destination = "/tmp/hosts_ip.txt"
  }

  provisioner "remote-exec" {
    inline = [
      "cat /tmp/hosts_ip.txt >> /etc/hosts",
    ]
  }
  count = var.masters >= 3 ? var.masters - 1 : 0
}

resource "null_resource" "workers-dns" {
  depends_on = [null_resource.workers-node]

  connection {
    type        = "ssh"
    host        = data.external.workers[count.index].result.ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "file" {
    source      = "/tmp/hosts_ip.txt"
    destination = "/tmp/hosts_ip.txt"
  }
  provisioner "remote-exec" {
    inline = [
      "cat /tmp/hosts_ip.txt >> /etc/hosts",
    ]
  }
  count = var.workers >= 1 ? var.workers : 0
}

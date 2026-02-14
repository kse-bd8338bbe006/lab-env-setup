resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.12.0"

  set {
    name  = "controller.service.type"
    value = "NodePort"
  }

  set {
    name  = "controller.service.nodePorts.http"
    value = "30080"
  }

  set {
    name  = "controller.service.nodePorts.https"
    value = "30443"
  }

  # Wait for the release to be deployed
  wait = true

  depends_on = [
    null_resource.workers-node,
    null_resource.kube_config
  ]
}

# Update HAProxy config after ingress is installed
resource "null_resource" "haproxy_ingress" {
  depends_on = [helm_release.nginx_ingress]

  triggers = {
    ingress_release = helm_release.nginx_ingress.version
  }

  connection {
    type        = "ssh"
    host        = local.haproxy_ip
    user        = "root"
    private_key = file(local.ssh_private_key)
  }

  provisioner "file" {
    source      = local_file.haproxy_ingress_cfg.filename
    destination = "/etc/haproxy/haproxy.cfg"
  }

  provisioner "remote-exec" {
    inline = [
      "systemctl restart haproxy"
    ]
  }
}

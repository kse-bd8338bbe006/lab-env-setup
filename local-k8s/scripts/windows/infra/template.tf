resource "local_file" "cloud_init_haproxy" {
  filename = "${path.module}/cloud-init-haproxy.yaml"
  content = templatefile("${path.module}/../script/cloud-init-haproxy.yaml", {
    ssh_public_key = file(local.ssh_public_key)
    static_ip      = local.haproxy_ip
    gateway        = var.network_gateway
    mac_address    = local.haproxy_mac
  })
}

resource "local_file" "cloud_init_master" {
  filename = "${path.module}/cloud-init-master.yaml"
  content = templatefile("${path.module}/../script/cloud-init.yaml", {
    k_version       = var.kube_version,
    k_minor_version = var.kube_minor_version,
    ssh_public_key  = file(local.ssh_public_key),
    extra_cmd       = "",
    haproxy_ip      = local.haproxy_ip
    static_ip       = local.master_ips[0]
    gateway         = var.network_gateway
    mac_address     = local.master_macs[0]
  })
}

resource "local_file" "cloud_init_masters" {
  count    = var.masters >= 3 ? 1 : 0
  filename = "${path.module}/cloud-init-masters.yaml"
  content = templatefile("${path.module}/../script/cloud-init.yaml", {
    k_version       = var.kube_version,
    k_minor_version = var.kube_minor_version,
    ssh_public_key  = file(local.ssh_public_key),
    extra_cmd       = "${data.external.kubejoin-master.result.join}",
    haproxy_ip      = ""
    static_ip       = local.master_ips[1]
    gateway         = var.network_gateway
    mac_address     = local.master_macs[1]
  })
}

# Generate individual cloud-init files for each worker with unique static IPs
resource "local_file" "cloud_init_worker" {
  count    = var.workers
  filename = "${path.module}/cloud-init-worker-${count.index}.yaml"
  content = templatefile("${path.module}/../script/cloud-init.yaml", {
    k_version       = var.kube_version,
    k_minor_version = var.kube_minor_version,
    ssh_public_key  = file(local.ssh_public_key),
    extra_cmd       = "${data.external.kubejoin.result.join}",
    haproxy_ip      = ""
    static_ip       = local.worker_ips[count.index]
    gateway         = var.network_gateway
    mac_address     = local.worker_macs[count.index]
  })
}

resource "local_file" "haproxy_initial_cfg" {
  filename = "${path.module}/haproxy_initial.cfg"
  content = templatefile("${path.module}/../script/haproxy.cfg.tpl", {
    master-0 = local.master_ips[0],
    master-1 = "",
    master-2 = ""
  })
}

resource "local_file" "haproxy_final_cfg" {
  filename = "${path.module}/haproxy_final.cfg"
  content = templatefile("${path.module}/../script/haproxy.cfg.tpl", {
    master-0 = local.master_ips[0],
    master-1 = var.masters > 1 ? local.master_ips[1] : "",
    master-2 = var.masters > 2 ? local.master_ips[2] : ""
  })
  count = var.masters == 3 ? 1 : 0
}

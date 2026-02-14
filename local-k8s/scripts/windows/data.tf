data "external" "haproxy" {
  program = ["pwsh", "-File", "${path.module}/script/multipass.ps1"]
  query = {
    name           = "haproxy"
    cpu            = var.cpu
    mem            = var.haproxy_mem
    disk           = var.haproxy_disk
    image          = var.ubuntu_image
    init           = local_file.cloud_init_haproxy.content
    network_switch = var.network_switch
    mac_address    = local.haproxy_mac
  }
}

data "external" "master" {
  program = ["pwsh", "-File", "${path.module}/script/multipass.ps1"]
  query = {
    name           = "master-${count.index}"
    cpu            = var.cpu
    mem            = var.master_mem
    disk           = var.disk
    image          = var.ubuntu_image
    init           = local_file.cloud_init_master.content
    network_switch = var.network_switch
    mac_address    = local.master_macs[count.index]
  }
  count      = 1
  depends_on = [data.external.haproxy]
}

data "external" "masters" {
  program = ["pwsh", "-File", "${path.module}/script/multipass.ps1"]
  query = {
    name           = "master-${count.index + 1}"
    cpu            = var.cpu
    mem            = var.master_mem
    disk           = var.disk
    image          = var.ubuntu_image
    init           = local_file.cloud_init_masters[0].content
    network_switch = var.network_switch
    mac_address    = local.master_macs[count.index + 1]
  }
  count      = var.masters >= 3 ? var.masters - 1 : 0
  depends_on = [data.external.master]
}

data "external" "workers" {
  program = ["pwsh", "-File", "${path.module}/script/multipass.ps1"]
  query = {
    name           = "worker-${count.index}"
    cpu            = var.worker_cpu
    mem            = var.worker_mem
    disk           = var.worker_disk
    image          = var.ubuntu_image
    init           = local_file.cloud_init_worker[count.index].content
    network_switch = var.network_switch
    mac_address    = local.worker_macs[count.index]
  }
  count      = var.workers >= 1 ? var.workers : 0
  depends_on = [data.external.masters]
}

data "external" "kubejoin-master" {
  depends_on = [null_resource.master-node]
  program = ["pwsh", "-Command",
    "ssh -i '${local.ssh_private_key}' -o StrictHostKeyChecking=no -l root ${local.master_ips[0]} cat /etc/join-master.json"
  ]
}

data "external" "kubejoin" {
  depends_on = [null_resource.master-node]
  program = ["pwsh", "-Command",
    "ssh -i '${local.ssh_private_key}' -o StrictHostKeyChecking=no -l root ${local.master_ips[0]} cat /etc/join.json"
  ]
}

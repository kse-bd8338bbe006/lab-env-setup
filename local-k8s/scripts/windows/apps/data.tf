data "terraform_remote_state" "infra" {
  backend = "local"
  config  = { path = "${path.module}/../infra/terraform.tfstate" }
}

locals {
  haproxy_ip      = data.terraform_remote_state.infra.outputs.haproxy_ip
  ssh_private_key = data.terraform_remote_state.infra.outputs.ssh_private_key
  master_ips      = data.terraform_remote_state.infra.outputs.master_ips
  worker_ips      = data.terraform_remote_state.infra.outputs.worker_ips
  masters_count   = data.terraform_remote_state.infra.outputs.masters_count
}

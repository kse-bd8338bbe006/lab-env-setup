variable "disk" {
  default     = "10G"
  type        = string
  description = "Disk size assigned to vms"
}
variable "worker_disk" {
  default     = "15G"
  type        = string
  description = "Disk size assigned to worker nodes"
}
variable "haproxy_disk" {
  default     = "30G"
  type        = string
  description = "Disk size assigned to HAProxy VM (includes NFS storage)"
}
variable "mem" {
  default     = "2G"
  type        = string
  description = "Memory assigned to vms"
}
variable "master_mem" {
  default     = "4G"
  type        = string
  description = "Memory assigned to master nodes"
}
variable "haproxy_mem" {
  default     = "4G"
  type        = string
  description = "Memory assigned to HAProxy VM"
}
variable "worker_mem" {
  default     = "3G"
  type        = string
  description = "Memory assigned to worker nodes"
}
variable "cpu" {
  default     = 2
  type        = number
  description = "Number of CPU assigned to vms"
}
variable "worker_cpu" {
  default     = 3
  type        = number
  description = "Number of CPU assigned to worker nodes"
}
variable "masters" {
  default     = 1
  type        = number
  description = "Number of control plane nodes"
}
variable "workers" {
  default     = 2
  type        = number
  description = "Number of worker nodes"
}
variable "kube_version" {
  default     = "1.32.11-1.1"
  type        = string
  description = "Version of Kubernetes to use"
}

variable "kube_minor_version" {
  default     = "1.32"
  type        = string
  description = "Kubernetes minor version for apt repository (e.g., 1.32)"
}

variable "ssh_key_name" {
  default     = "kse_ci_cd_sec_id_rsa"
  type        = string
  description = "Name of SSH key files (without extension) in USERPROFILE\\.ssh directory"
}

variable "ubuntu_image" {
  default     = "22.04"
  type        = string
  description = "Ubuntu image version for VMs (e.g., 22.04, 24.04). Run 'multipass find' to see available images."
}

# Network configuration for static IPs
variable "network_switch" {
  default     = "K8sSwitch"
  type        = string
  description = "Hyper-V switch name for VMs (created by setup-network.ps1)"
}

variable "network_gateway" {
  default     = "192.168.50.1"
  type        = string
  description = "Gateway IP for the K8s network (Windows host)"
}

variable "network_prefix" {
  default     = "192.168.50"
  type        = string
  description = "Network prefix for static IPs (first 3 octets)"
}

variable "haproxy_ip_suffix" {
  default     = 10
  type        = number
  description = "Last octet of HAProxy IP (e.g., 10 for 192.168.50.10)"
}

variable "master_ip_start" {
  default     = 11
  type        = number
  description = "Starting last octet for master nodes (e.g., 11 for 192.168.50.11)"
}

variable "worker_ip_start" {
  default     = 21
  type        = number
  description = "Starting last octet for worker nodes (e.g., 21 for 192.168.50.21)"
}

locals {
  ssh_dir         = pathexpand("~/.ssh")
  ssh_private_key = "${local.ssh_dir}/${var.ssh_key_name}"
  ssh_public_key  = "${local.ssh_dir}/${var.ssh_key_name}.pub"
  hosts_ip_file   = "${pathexpand("~/AppData/Local/Temp")}/hosts_ip.txt"

  # Computed static IPs
  haproxy_ip = "${var.network_prefix}.${var.haproxy_ip_suffix}"
  master_ips = [for i in range(var.masters) : "${var.network_prefix}.${var.master_ip_start + i}"]
  worker_ips = [for i in range(var.workers) : "${var.network_prefix}.${var.worker_ip_start + i}"]

  # Generated MAC addresses (using 52:54:00 prefix - common for virtual NICs)
  # Format: 52:54:00:XX:YY:ZZ where XX:YY:ZZ derived from IP suffix
  mac_prefix  = "52:54:00"
  haproxy_mac = "${local.mac_prefix}:c8:32:${format("%02x", var.haproxy_ip_suffix)}"
  master_macs = [for i in range(var.masters) : "${local.mac_prefix}:c8:32:${format("%02x", var.master_ip_start + i)}"]
  worker_macs = [for i in range(var.workers) : "${local.mac_prefix}:c8:32:${format("%02x", var.worker_ip_start + i)}"]
}

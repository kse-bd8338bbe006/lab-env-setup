# Terraform Kubernetes Multipass - macOS

This module provisions a production-like Kubernetes cluster using Multipass on macOS (QEMU) with static IP configuration, monitoring, GitOps, and persistent storage.

## Prerequisites

- macOS 10.15+ (Apple Silicon or Intel)
- [Multipass](https://multipass.run/) installed (QEMU driver)
- [Terraform](https://www.terraform.io/downloads.html) installed
- SSH key pair in `~/.ssh/` (kse_ci_cd_sec_id_rsa)

## Quick Start

```bash
# 1. Initialize Terraform
terraform init

# 2. Create cluster (VMs + Kubernetes)
terraform apply

# 3. Enable host connectivity to static IPs
sudo ./setup-network.sh

# 4. Complete helm chart installations
terraform apply

# After VM restarts or macOS reboots, re-run:
sudo ./setup-network.sh

# 5. Access your cluster
export KUBECONFIG=~/.kube/config-multipass
kubectl get nodes
```

## Network Configuration

VMs use dual NICs with static IP addresses on an isolated bridge:

| VM | Static IP (k8snet) | Resources | Purpose |
|----|---------------------|-----------|---------|
| haproxy | 192.168.50.10 | 2 CPU, 4G RAM, 30G disk | Load balancer, NFS server, PostgreSQL |
| master-0 | 192.168.50.11 | 2 CPU, 4G RAM, 10G disk | Kubernetes control plane |
| worker-0 | 192.168.50.21 | 3 CPU, 3G RAM, 15G disk | Kubernetes worker node |
| worker-1 | 192.168.50.22 | 3 CPU, 3G RAM, 15G disk | Kubernetes worker node |

See [macOS QEMU Network Configuration](../../docs/macos-qemu-networking.md) for the full architecture.

## What Gets Installed

| Application | Version | URL | Credentials |
|-------------|---------|-----|-------------|
| **ArgoCD** | 7.7.10 | http://argocd.192.168.50.10.nip.io | admin / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| **Grafana** | 12.3.1 | http://grafana.192.168.50.10.nip.io | admin / admin |
| **Prometheus** | Latest | http://prometheus.192.168.50.10.nip.io | - |
| **AlertManager** | Latest | http://alertmanager.192.168.50.10.nip.io | - |
| **NGINX Ingress** | 4.12.0 | - | - |
| **NFS Provisioner** | 4.0.18 | - | StorageClass: `nfs-client` |
| **PostgreSQL** | Latest | 192.168.50.10:5432 | postgres / `multipass exec haproxy -- cat /root/postgres_credentials.txt` |

## Clean Up

```bash
terraform destroy
sudo ./reset.sh
```

---

<!-- BEGIN_AUTOMATED_TF_DOCS_BLOCK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_external"></a> [external](#requirement\_external) | 2.3.1 |
| <a name="requirement_local"></a> [local](#requirement\_local) | 2.4.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | 3.2.1 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.5.1 |
## Usage
Basic usage of this module is as follows:
```hcl
module "example" {
	 source  = "<module-path>"

	 # Optional variables
	 cpu  = 2
	 disk  = "10G"
	 kube_version  = "1.28.2-1.1"
	 masters  = 1
	 mem  = "2G"
	 workers  = 3
}
```
## Resources

| Name | Type |
|------|------|
| [local_file.cloud_init_haproxy](https://registry.terraform.io/providers/hashicorp/local/2.4.0/docs/resources/file) | resource |
| [local_file.cloud_init_master](https://registry.terraform.io/providers/hashicorp/local/2.4.0/docs/resources/file) | resource |
| [local_file.cloud_init_masters](https://registry.terraform.io/providers/hashicorp/local/2.4.0/docs/resources/file) | resource |
| [local_file.cloud_init_workers](https://registry.terraform.io/providers/hashicorp/local/2.4.0/docs/resources/file) | resource |
| [local_file.haproxy_final_cfg](https://registry.terraform.io/providers/hashicorp/local/2.4.0/docs/resources/file) | resource |
| [local_file.haproxy_initial_cfg](https://registry.terraform.io/providers/hashicorp/local/2.4.0/docs/resources/file) | resource |
| [null_resource.haproxy](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [null_resource.haproxy-dns](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [null_resource.haproxy_final](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [null_resource.kube_config](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [null_resource.master-dns](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [null_resource.master-node](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [null_resource.masters-dns](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [null_resource.masters-node](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [null_resource.workers-dns](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [null_resource.workers-node](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [external_external.haproxy](https://registry.terraform.io/providers/hashicorp/external/2.3.1/docs/data-sources/external) | data source |
| [external_external.kubejoin](https://registry.terraform.io/providers/hashicorp/external/2.3.1/docs/data-sources/external) | data source |
| [external_external.kubejoin-master](https://registry.terraform.io/providers/hashicorp/external/2.3.1/docs/data-sources/external) | data source |
| [external_external.master](https://registry.terraform.io/providers/hashicorp/external/2.3.1/docs/data-sources/external) | data source |
| [external_external.masters](https://registry.terraform.io/providers/hashicorp/external/2.3.1/docs/data-sources/external) | data source |
| [external_external.workers](https://registry.terraform.io/providers/hashicorp/external/2.3.1/docs/data-sources/external) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Number of CPU assigned to vms | `number` | `2` | no |
| <a name="input_disk"></a> [disk](#input\_disk) | Disk size assigned to vms | `string` | `"10G"` | no |
| <a name="input_kube_version"></a> [kube\_version](#input\_kube\_version) | Version of Kubernetes to use | `string` | `"1.28.2-1.1"` | no |
| <a name="input_masters"></a> [masters](#input\_masters) | Number of control plane nodes | `number` | `1` | no |
| <a name="input_mem"></a> [mem](#input\_mem) | Memory assigned to vms | `string` | `"2G"` | no |
| <a name="input_workers"></a> [workers](#input\_workers) | Number of worker nodes | `number` | `3` | no |
## Outputs

No outputs.
<!-- END_AUTOMATED_TF_DOCS_BLOCK -->

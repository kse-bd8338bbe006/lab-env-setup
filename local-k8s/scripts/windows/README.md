# Terraform Kubernetes Multipass - Windows (Hyper-V)

This module provisions a production-like Kubernetes cluster using Multipass on Windows with Hyper-V, static IP configuration, monitoring, GitOps, and persistent storage.

Terraform is split into two phases to solve the provider initialization problem:
- **infra/** - Creates VMs, bootstraps the K8s cluster, and generates kubeconfig
- **apps/** - Deploys applications using kubernetes/helm providers (requires kubeconfig from infra)

## Prerequisites

- Windows 10/11 with Hyper-V enabled
- [Multipass](https://multipass.run/) installed
- [Terraform](https://www.terraform.io/downloads.html) installed
- PowerShell 7+ recommended
- SSH key pair in `%USERPROFILE%\.ssh\` (kse_ci_cd_sec_id_rsa)

## Quick Start

### Automated (Recommended)

Run the full setup with a single command:

```cmd
create-cluster.cmd
```

Or directly with PowerShell:

```powershell
.\create-cluster.ps1
```

This handles network setup, Terraform init/apply for both infra and apps, and kubeconfig configuration. Progress and errors are logged to `logs/create-cluster_<timestamp>.log`.

### Manual

1. Set up the Hyper-V network (run as Administrator):
```powershell
.\setup-network.ps1
```

2. Deploy infrastructure (VMs + K8s cluster):
```powershell
terraform -chdir=infra init
terraform -chdir=infra apply -auto-approve
```

3. Deploy applications:
```powershell
terraform -chdir=apps init
terraform -chdir=apps apply -auto-approve
```

4. Access your cluster:
```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-multipass"
kubectl get nodes
```

## Directory Structure

```
windows/
├── infra/                   Terraform: VM creation, K8s bootstrap, kubeconfig
│   ├── versions.tf          Providers: external, null, local
│   ├── variables.tf         All configuration variables
│   ├── data.tf              Multipass VM creation via external data source
│   ├── template.tf          Cloud-init and HAProxy config generation
│   ├── master.tf            Master node initialization (kubeadm init)
│   ├── workers.tf           Worker node join verification
│   ├── more_masters.tf      Additional masters (HA setup, masters=3)
│   ├── haproxy.tf           HAProxy initial config deployment
│   ├── haproxy_final.tf     HAProxy HA config (masters=3)
│   ├── dns.tf               /etc/hosts distribution
│   ├── storage.tf           NFS server + PostgreSQL on HAProxy VM
│   ├── kube_config.tf       Retrieve kubeconfig from master
│   └── outputs.tf           Exports IPs, SSH key for apps/
├── apps/                    Terraform: K8s application deployment
│   ├── versions.tf          Providers: kubernetes, helm, random, null, local
│   ├── data.tf              Reads infra state via terraform_remote_state
│   ├── ingress.tf           NGINX Ingress Controller + HAProxy update
│   ├── storage.tf           NFS Subdir External Provisioner (StorageClass)
│   ├── monitoring.tf        Prometheus, Grafana, AlertManager
│   ├── argocd.tf            ArgoCD GitOps
│   ├── vault.tf             HashiCorp Vault + External Secrets Operator
│   ├── harbor.tf            Harbor container registry
│   └── dependency-track.tf  Dependency-Track (disabled)
├── script/                  Shared scripts and templates
│   ├── multipass.ps1        Multipass VM creation helper
│   ├── kube-init.sh         Kubernetes master initialization
│   ├── cloud-init.yaml      Cloud-init template for K8s nodes
│   ├── cloud-init-haproxy.yaml  Cloud-init template for HAProxy
│   ├── haproxy.cfg.tpl      HAProxy initial config template
│   └── haproxy-ingress.cfg.tpl  HAProxy ingress config template
├── create-cluster.ps1       Full orchestration with logging
├── create-cluster.cmd       Wrapper for create-cluster.ps1
├── destroy-cluster.ps1      Full cleanup with logging
├── destroy-cluster.cmd      Wrapper for destroy-cluster.ps1
├── setup-network.ps1        Hyper-V network setup (run as Admin)
└── reset.ps1                Quick cleanup of VMs and state
```

## What Gets Installed

| Application | Version | URL | Credentials |
|-------------|---------|-----|-------------|
| **ArgoCD** | 7.7.10 | http://argocd.192.168.50.10.nip.io | admin / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| **Grafana** | 12.3.1 | http://grafana.192.168.50.10.nip.io | admin / admin |
| **Prometheus** | Latest | http://prometheus.192.168.50.10.nip.io | - |
| **AlertManager** | Latest | http://alertmanager.192.168.50.10.nip.io | - |
| **Vault** | 0.28.1 | http://vault.192.168.50.10.nip.io | `kubectl -n vault get secret vault-unseal-key -o jsonpath='{.data.root-token}' \| base64 -d` |
| **Harbor** | 1.18.1 | http://harbor.192.168.50.10.nip.io | admin / `terraform -chdir=apps output -raw harbor_admin_password` |
| **NGINX Ingress** | 4.12.0 | - | - |
| **NFS Provisioner** | 4.0.18 | - | StorageClass: `nfs-client` |
| **PostgreSQL** | Latest | 192.168.50.10:5432 | postgres / `multipass exec haproxy -- cat /root/postgres_credentials.txt` |

## Network Configuration

Static IP addresses are assigned to all VMs:

| VM | IP Address | Resources | Purpose |
|----|------------|-----------|---------|
| haproxy | 192.168.50.10 | 2 CPU, 4G RAM, 30G disk | Load balancer, NFS server, PostgreSQL |
| master-0 | 192.168.50.11 | 2 CPU, 4G RAM, 10G disk | Kubernetes control plane |
| worker-0 | 192.168.50.21 | 3 CPU, 3G RAM, 15G disk | Kubernetes worker node |
| worker-1 | 192.168.50.22 | 3 CPU, 3G RAM, 15G disk | Kubernetes worker node |

## Variables

Variables are defined in `infra/variables.tf`:

| Name | Description | Type | Default |
|------|-------------|------|---------|
| cpu | Number of CPU assigned to vms | number | 2 |
| worker_cpu | Number of CPU for worker nodes | number | 3 |
| master_mem | Memory for master nodes | string | "4G" |
| haproxy_mem | Memory for HAProxy VM | string | "4G" |
| worker_mem | Memory for worker nodes | string | "3G" |
| haproxy_disk | Disk size for HAProxy (NFS storage) | string | "30G" |
| worker_disk | Disk size for worker nodes | string | "15G" |
| kube_version | Version of Kubernetes to use | string | "1.32.11-1.1" |
| masters | Number of control plane nodes | number | 1 |
| workers | Number of worker nodes | number | 2 |
| ubuntu_image | Ubuntu image version | string | "22.04" |
| ssh_key_name | SSH key name in USERPROFILE\.ssh | string | "kse_ci_cd_sec_id_rsa" |

## Storage

The cluster uses NFS-based persistent storage:

- **NFS Server**: HAProxy VM (192.168.50.10)
- **NFS Path**: /srv/nfs/k8s-storage
- **StorageClass**: `nfs-client` (default)
- **Access Mode**: ReadWriteMany

Example PVC:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: nfs-client
```

## Clean Up

Automated (with confirmation prompt):
```cmd
destroy-cluster.cmd
```

Or manually:
```powershell
terraform -chdir=apps destroy -auto-approve
terraform -chdir=infra destroy -auto-approve
multipass delete --all && multipass purge
```

Quick reset (deletes VMs and all state):
```powershell
.\reset.ps1
```

## Notes

- SSH connections from Terraform to VMs use the key at `%USERPROFILE%\.ssh\kse_ci_cd_sec_id_rsa`
- Kubeconfig is automatically copied to `%USERPROFILE%\.kube\config-multipass` and `%USERPROFILE%\.kube\config`
- All services are accessible via nip.io DNS (resolves to 192.168.50.10)
- CNI: Weave Net v2.8.1
- Logs are saved to `logs/` directory with timestamps

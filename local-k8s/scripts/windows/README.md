# Terraform Kubernetes Multipass - Windows

This module provisions a production-like Kubernetes cluster using Multipass on Windows with static IP configuration, monitoring, GitOps, and persistent storage.

## Prerequisites

- Windows 10/11 with Hyper-V enabled
- [Multipass](https://multipass.run/) installed
- [Terraform](https://www.terraform.io/downloads.html) installed
- PowerShell 7+ recommended
- SSH key pair in `%USERPROFILE%\.ssh\` (kse_ci_cd_sec_id_rsa)

## Network Setup

Before running Terraform, set up the Hyper-V network switch:

```powershell
# Run as Administrator
.\setup-network.ps1
```

This creates a Hyper-V internal switch named `K8sSwitch` with the 192.168.50.0/24 network.

## Quick Start

1. Ensure Multipass is installed and running:
```powershell
multipass version
```

2. Initialize Terraform:
```powershell
terraform init
```

3. Apply the configuration:
```powershell
terraform apply
```

4. Access your cluster:
```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-multipass"
kubectl get nodes
```

## What Gets Installed

The cluster comes with these pre-installed applications:

| Application | Version | URL | Credentials |
|-------------|---------|-----|-------------|
| **ArgoCD** | 7.7.10 | http://argocd.192.168.50.10.nip.io | admin / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| **Grafana** | 12.3.1 | http://grafana.192.168.50.10.nip.io | admin / admin |
| **Prometheus** | Latest | http://prometheus.192.168.50.10.nip.io | - |
| **AlertManager** | Latest | http://alertmanager.192.168.50.10.nip.io | - |
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

| Name | Description | Type | Default |
|------|-------------|------|---------|
| cpu | Number of CPU assigned to vms | number | 2 |
| worker_cpu | Number of CPU for worker nodes | number | 3 |
| mem | Memory assigned to vms (default) | string | "2G" |
| master_mem | Memory for master nodes | string | "4G" |
| haproxy_mem | Memory for HAProxy VM | string | "4G" |
| worker_mem | Memory for worker nodes | string | "3G" |
| disk | Disk size for vms (default) | string | "10G" |
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

To destroy all resources:
```powershell
terraform destroy
.\reset.ps1
```

## Notes

- SSH connections from Terraform to VMs use the key at `%USERPROFILE%\.ssh\kse_ci_cd_sec_id_rsa`
- Kubeconfig is automatically copied to `%USERPROFILE%\.kube\config-multipass` and `%USERPROFILE%\.kube\config`
- All services are accessible via nip.io DNS (resolves to 192.168.50.10)
- CNI: Weave Net v2.8.1

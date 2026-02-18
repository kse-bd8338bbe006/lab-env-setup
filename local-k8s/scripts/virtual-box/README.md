# Kubernetes Cluster Setup with VirtualBox (Vagrant)

This directory contains scripts to deploy a local Kubernetes cluster using Vagrant with VirtualBox. This setup is intended for Windows Home edition users who cannot use Hyper-V.

> **Prerequisites**
>
> - Windows 10/11 Home (or Pro/Enterprise with Hyper-V disabled)
> - VirtualBox 7.0+ installed
> - Vagrant 2.4+ installed
> - Terraform 1.0+ installed
> - SSH key pair at `%USERPROFILE%\.ssh\kse_ci_cd_sec_id_rsa`

---

## 1. Overview

This setup uses Vagrant to create VirtualBox VMs for a Kubernetes cluster, then Terraform to deploy applications.

- **HAProxy VM**: Load balancer, NFS server, PostgreSQL (192.168.56.10)
- **Master Node**: Kubernetes control plane (192.168.56.11)
- **Worker Nodes**: Kubernetes worker nodes (192.168.56.21-22)

### 1.1 Dual-Adapter VM Architecture

Each VM has two network adapters:

| Adapter | Purpose | IP Assignment |
|---------|---------|---------------|
| enp0s3 | Internet access | Dynamic (VirtualBox NAT) |
| enp0s8 | Cluster communication | Static (Host-Only 192.168.56.x) |

This allows VMs to download packages/images via enp0s3 while maintaining stable static IPs on enp0s8 for Kubernetes.

### 1.2 Differences from Hyper-V Setup

| Feature | Hyper-V | VirtualBox |
|---------|---------|------------|
| Provisioner | Multipass + Terraform | Vagrant |
| Cluster subnet | 192.168.50.x | 192.168.56.x |
| Network setup | K8sSwitch (virtual switch) | VirtualBox Host-Only Adapter |
| Internet access | Windows NetNat | VirtualBox NAT |

---

## 2. Setup Instructions

### 2.1 Install VirtualBox

Download and install VirtualBox from [virtualbox.org](https://www.virtualbox.org/wiki/Downloads).

### 2.2 Install Vagrant

Download and install Vagrant from [vagrantup.com](https://www.vagrantup.com/downloads).

### 2.3 Verify VirtualBox Host-Only Network

The Host-Only adapter should be created automatically. Verify it exists:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list hostonlyifs
```

Expected output should show an adapter with IP 192.168.56.1.

### 2.4 Deploy Cluster

```powershell
cd scripts\virtual-box
powershell -ExecutionPolicy Bypass -File create-cluster.ps1
```

The script will:
1. Create and provision each VM sequentially (haproxy -> master -> workers)
2. Validate provisioning succeeded before proceeding
3. Run `terraform -chdir=infra apply` to configure the cluster and generate kubeconfig
4. Run `terraform -chdir=apps apply` to deploy applications (ingress, monitoring, ArgoCD, Harbor, Vault)

The first run downloads the Ubuntu box (~800MB) and creates VMs. Subsequent runs use cached images.

---

## 3. Directory Structure

Terraform code is split into two directories to solve the provider initialization problem. The kubernetes/helm providers require a valid kubeconfig at plan time, but the kubeconfig does not exist until the cluster is created. Separating infrastructure from applications ensures that `infra/` creates the cluster and kubeconfig first, then `apps/` deploys helm charts with a kubeconfig guaranteed to exist.

```
virtual-box/
  Vagrantfile              # VM definitions for Vagrant
  create-cluster.ps1       # Main setup script
  destroy-cluster.ps1      # Teardown script
  cleanup-vagrant.ps1      # Fix stale Vagrant state
  script/                  # Shared provisioning templates
  infra/                   # Terraform: cluster setup (null, external, local providers)
    variables.tf, data.tf, template.tf, master.tf, workers.tf,
    haproxy.tf, dns.tf, kube_config.tf, storage.tf, outputs.tf
  apps/                    # Terraform: application deployment (kubernetes, helm providers)
    data.tf, ingress.tf, storage.tf, argocd.tf, harbor.tf,
    vault.tf, monitoring.tf, dependency-track.tf
```

## 4. Scripts

| Script | Purpose |
|--------|---------|
| `create-cluster.ps1` | Creates all VMs and deploys applications with Terraform |
| `destroy-cluster.ps1` | Destroys all VMs, Terraform state, and orphaned resources |
| `cleanup-vagrant.ps1` | Fixes stale locks and reconciles Vagrant state without destroying VMs |

> **Note on Windows process handling**: Vagrant on Windows may detach from its
> Ruby child process during `vagrant up`, causing premature exit codes.
> The PowerShell scripts handle this by waiting for background provisioning
> and validating results. If vagrant commands fail with "another process is
> already executing an action", run `cleanup-vagrant.ps1`.

---

## 5. VM Management

### 6.1 Common Commands

```powershell
# Check VM status
vagrant status

# SSH into a VM
vagrant ssh haproxy
vagrant ssh master-0

# Check Kubernetes nodes
vagrant ssh master-0 -c "kubectl get nodes"

# Stop all VMs (preserves state)
vagrant halt

# Start stopped VMs
vagrant up

# Destroy and recreate
powershell -ExecutionPolicy Bypass -File destroy-cluster.ps1
powershell -ExecutionPolicy Bypass -File create-cluster.ps1
```

### 6.2 VM Specifications

| VM | IP | Memory | CPUs | Purpose |
|----|-----|--------|------|---------|
| haproxy | 192.168.56.10 | 4096MB | 2 | Load balancer, NFS, PostgreSQL |
| master-0 | 192.168.56.11 | 4096MB | 2 | Control plane |
| worker-0 | 192.168.56.21 | 3072MB | 3 | Worker node |
| worker-1 | 192.168.56.22 | 3072MB | 3 | Worker node |

---

## 6. Verification

### 6.1 Check VMs

```powershell
vagrant status
```

Expected output:
```
haproxy                   running (virtualbox)
master-0                  running (virtualbox)
worker-0                  running (virtualbox)
worker-1                  running (virtualbox)
```

### 6.2 Test Connectivity

```powershell
ping 192.168.56.10  # HAProxy
ping 192.168.56.11  # Master
```

### 6.3 Kubernetes Status

```powershell
vagrant ssh master-0 -c "kubectl get nodes -o wide"
```

---

## 7. Access Services

After Terraform deployment, the following services are available:

| Service | URL |
|---------|-----|
| ArgoCD | http://argocd.192.168.56.10.nip.io |
| Harbor | http://harbor.192.168.56.10.nip.io |
| Vault | http://vault.192.168.56.10.nip.io |
| Grafana | http://grafana.192.168.56.10.nip.io |
| Prometheus | http://prometheus.192.168.56.10.nip.io |
| AlertManager | http://alertmanager.192.168.56.10.nip.io |
| HAProxy Stats | http://192.168.56.10:8404/stats (admin/admin) |

Service credentials and URLs are available via `terraform -chdir=apps output`.

---

## 8. Troubleshooting

### 8.1 "Another process is already executing an action"

This happens when a previous vagrant command left stale locks. Run:

```powershell
powershell -ExecutionPolicy Bypass -File cleanup-vagrant.ps1
```

### 8.2 VM Creation Fails

Check VirtualBox is installed and working:
```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version
```

### 8.3 Network Issues

Verify Host-Only adapter:
```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list hostonlyifs
```

If missing or wrong IP, create it:
```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" hostonlyif create
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" --ip 192.168.56.1 --netmask 255.255.255.0
```

### 8.4 Box Download Fails

Manually add the box:
```powershell
vagrant box add ubuntu/jammy64
```

### 8.5 Terraform Fails with "Unauthorized"

```
Error: Failed to create Ingress 'argocd/argocd-ingress' because: Unauthorized
```

The kubeconfig at `~/.kube/config-virtualbox` contains client certificates from a
previous cluster. After destroying and recreating VMs, kubeadm generates a new CA,
so the old credentials are no longer valid.

**Fix**: Re-fetch the kubeconfig from the master node:

```powershell
vagrant ssh master-0 -c "sudo cat /etc/kubernetes/admin.conf" > "$env:USERPROFILE\.kube\config-virtualbox"
Copy-Item "$env:USERPROFILE\.kube\config-virtualbox" "$env:USERPROFILE\.kube\config" -Force
```

Then re-run terraform:

```powershell
terraform -chdir=apps apply -auto-approve
```

### 8.6 Terraform Fails with "x509: certificate signed by unknown authority"

```
Error: Failed to create Ingress ... tls: failed to verify certificate: x509: certificate signed by unknown authority
```

The Kubernetes API server uses a self-signed CA certificate generated by kubeadm.
When HAProxy's TCP idle timeout (50s) resets a long-lived connection, the Terraform
provider must re-establish TLS. The Go TLS library then rejects the self-signed CA.

**Fix**: Ensure `insecure = true` is set in both provider blocks in `apps/versions.tf`:

```hcl
provider "kubernetes" {
  config_path = pathexpand("~/.kube/config-virtualbox")
  insecure    = true
}

provider "helm" {
  kubernetes {
    config_path = pathexpand("~/.kube/config-virtualbox")
    insecure    = true
  }
}
```

This is safe for a local lab environment. Do not use `insecure = true` in production.

### 8.7 VMs Run Out of Memory

Modify `VM_SPECS` in `Vagrantfile` to reduce memory allocation:
```ruby
"master-0" => { ip_suffix: 11, memory: 2048, cpus: 2, role: "master" },
```

---

## 9. Cleanup

Destroy all VMs and state:
```powershell
powershell -ExecutionPolicy Bypass -File destroy-cluster.ps1
```

To also remove the downloaded base box:
```powershell
vagrant box remove ubuntu/jammy64
```

---

## 10. Customization

### 10.1 Modify VM Specifications

Edit the `VM_SPECS` hash in `Vagrantfile`:

```ruby
VM_SPECS = {
  "haproxy"  => { ip_suffix: 10, memory: 4096, cpus: 2, role: "haproxy" },
  "master-0" => { ip_suffix: 11, memory: 4096, cpus: 2, role: "master" },
  # ...
}
```

### 10.2 Add More Nodes

Add entries to `VM_SPECS`:

```ruby
  "worker-2" => { ip_suffix: 23, memory: 3072, cpus: 3, role: "worker" },
  "worker-3" => { ip_suffix: 24, memory: 3072, cpus: 3, role: "worker" },
```

### 10.3 Change Subnet

Modify `NETWORK_PREFIX` in `Vagrantfile`:

```ruby
NETWORK_PREFIX = "192.168.100"
```

Note: You may need to create a matching VirtualBox Host-Only adapter.

# Lab Environment Setup

This repository contains automation scripts for provisioning a local Kubernetes cluster used in the CI/CD Security course. The cluster hosts applications required for lab exercises: ArgoCD, Vault, Grafana, Prometheus and External Secret Operator, etc.

Three platform-specific setups are provided. Each produces the same cluster topology by default - an HAProxy load balancer, one control plane node, and two worker nodes - but uses different virtualization backends.

---

## Setup Guides

Choose the guide that matches your operating system and hypervisor.

| Platform | Hypervisor | Provisioner | Guide |
|----------|------------|-------------|-------|
| Windows (Pro/Enterprise) | Hyper-V | Multipass + Terraform | [windows/README.md](local-k8s/scripts/windows/README.md) |
| Windows (Home) | VirtualBox | Vagrant + Terraform | [virtual-box/README.md](local-k8s/scripts/virtual-box/README.md) |
| macOS | QEMU | Multipass + Terraform | [macos/README.md](local-k8s/scripts/macos/README.md) |

> **Which setup should I use?**
>
> - **Windows Pro/Enterprise with Hyper-V enabled** - use the Hyper-V setup. It is the primary tested configuration.
> - **Windows Home or Hyper-V unavailable** - use the VirtualBox setup. 
> - **macOS (Apple Silicon or Intel)** - use the macOS setup with QEMU driver.

---

## Documentation

Additional reference materials are available in the [docs/](local-k8s/docs/) directory.

| Document | Description |
|----------|-------------|
| [Lab Setup Guide](local-k8s/docs/setup-guide.md) | Step-by-step setup instructions with hardware requirements and prerequisites |
| [Setup Lab](local-k8s/docs/setup-lab.md) | GitHub organization creation, repository forking, and initial lab configuration |
| [Kubernetes Configuration](local-k8s/docs/k8s-conf.md) | Cluster architecture, network configuration, provisioning flow, and cloud-init templates |
| [Vault + ESO Architecture](local-k8s/docs/vault-eso-architecture.md) | Vault deployment, initialization, and External Secrets Operator integration |
| [macOS QEMU Networking](local-k8s/docs/macos-qemu-networking.md) | Dual-NIC networking architecture for macOS with QEMU hypervisor |
| [Troubleshooting](local-k8s/docs/troubleshooting.md) | Common issues and fixes for Multipass on Windows |

---

## Repository Structure

```
lab-env-setup/
  local-k8s/
    docs/                          # Reference documentation
    scripts/
      windows/                     # Hyper-V + Multipass setup
      virtual-box/                 # VirtualBox + Vagrant setup
      macos/                       # QEMU + Multipass setup
```

---

## Cluster Topology

All three setups create the same four-node cluster.

| Node | Role | Services |
|------|------|----------|
| haproxy | Load balancer | HAProxy, NFS server, PostgreSQL |
| master-0 | Control plane | Kubernetes API server, etcd, scheduler |
| worker-0 | Worker | Application workloads |
| worker-1 | Worker | Application workloads |

Applications deployed by Terraform after cluster creation:

| Application | Purpose |
|-------------|---------|
| NGINX Ingress | Ingress controller for HTTP routing |
| NFS Provisioner | Dynamic persistent volume provisioning |
| ArgoCD | GitOps continuous delivery |
| Vault | Secrets management |
| Prometheus + Grafana | Monitoring and dashboards |

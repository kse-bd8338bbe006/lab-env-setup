# Data sources for Vagrant-created VMs
# VMs are created by Vagrant, not Terraform
# This file provides the same interface as Multipass-based data.tf

# HAProxy VM - created by Vagrant
data "external" "haproxy" {
  program = ["pwsh", "-Command", "Write-Output ('{\"ip\":\"' + '${local.haproxy_ip}' + '\"}')"]
}

# Master VM - created by Vagrant
data "external" "master" {
  program = ["pwsh", "-Command", "Write-Output ('{\"ip\":\"' + '${local.master_ips[count.index]}' + '\"}')"]
  count   = 1
}

# Additional masters (not used in single-master setup)
data "external" "masters" {
  program = ["pwsh", "-Command", "Write-Output ('{\"ip\":\"' + '${local.master_ips[count.index + 1]}' + '\"}')"]
  count   = var.masters >= 3 ? var.masters - 1 : 0
}

# Worker VMs - created by Vagrant
data "external" "workers" {
  program = ["pwsh", "-Command", "Write-Output ('{\"ip\":\"' + '${local.worker_ips[count.index]}' + '\"}')"]
  count   = var.workers >= 1 ? var.workers : 0
}

# Get join commands from master (after Vagrant has initialized K8s)
data "external" "kubejoin-master" {
  depends_on = [null_resource.wait_for_k8s]
  program = ["pwsh", "-Command",
    "ssh -i '${local.ssh_private_key}' -o StrictHostKeyChecking=no -l root ${local.master_ips[0]} cat /etc/join-master.json"
  ]
}

data "external" "kubejoin" {
  depends_on = [null_resource.wait_for_k8s]
  program = ["pwsh", "-Command",
    "ssh -i '${local.ssh_private_key}' -o StrictHostKeyChecking=no -l root ${local.master_ips[0]} cat /etc/join.json"
  ]
}

# Wait for Kubernetes to be ready (Vagrant provisioning completes)
resource "null_resource" "wait_for_k8s" {
  provisioner "local-exec" {
    command     = <<-EOT
      Write-Host "Waiting for Kubernetes API to be ready..."
      $maxRetries = 30
      $retryCount = 0
      while ($retryCount -lt $maxRetries) {
        try {
          $result = ssh -i '${local.ssh_private_key}' -o StrictHostKeyChecking=no -o ConnectTimeout=5 -l root ${local.master_ips[0]} "kubectl get nodes" 2>&1
          if ($result -match "Ready") {
            Write-Host "Kubernetes is ready!"
            exit 0
          }
        } catch {}
        $retryCount++
        Write-Host "Waiting... ($retryCount/$maxRetries)"
        Start-Sleep -Seconds 10
      }
      Write-Error "Timeout waiting for Kubernetes"
      exit 1
    EOT
    interpreter = ["pwsh", "-Command"]
  }
}

resource "null_resource" "kube_config" {
  depends_on = [null_resource.master-node]
  provisioner "local-exec" {
    command = <<CMD
if (!(Test-Path "$env:USERPROFILE\.kube")) { New-Item -ItemType Directory -Path "$env:USERPROFILE\.kube" -Force }
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -i "${local.ssh_private_key}" root@${local.master_ips[0]}:/etc/kubernetes/admin.conf "$env:USERPROFILE\.kube\config-multipass"
Copy-Item "$env:USERPROFILE\.kube\config-multipass" "$env:USERPROFILE\.kube\config" -Force
# Ensure context exists (SCP on Windows can mangle YAML)
kubectl --kubeconfig "$env:USERPROFILE\.kube\config-multipass" config set-context kubernetes-admin@kubernetes --cluster=kubernetes --user=kubernetes-admin
kubectl --kubeconfig "$env:USERPROFILE\.kube\config-multipass" config use-context kubernetes-admin@kubernetes
Copy-Item "$env:USERPROFILE\.kube\config-multipass" "$env:USERPROFILE\.kube\config" -Force
CMD
    interpreter = ["pwsh", "-Command"]
  }
}

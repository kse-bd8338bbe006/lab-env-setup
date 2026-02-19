output "haproxy_ip" {
  value       = local.haproxy_ip
  description = "HAProxy VM IP address"
}

output "ssh_private_key" {
  value       = local.ssh_private_key
  description = "Path to SSH private key"
}

output "master_ips" {
  value       = local.master_ips
  description = "Master node IP addresses"
}

output "worker_ips" {
  value       = local.worker_ips
  description = "Worker node IP addresses"
}

output "masters_count" {
  value       = var.masters
  description = "Number of master nodes"
}

output "postgresql_host" {
  value       = local.haproxy_ip
  description = "PostgreSQL host IP"
}

output "postgresql_credentials_command" {
  value       = "multipass exec haproxy -- cat /root/postgres_credentials.txt"
  description = "Command to retrieve PostgreSQL password"
}

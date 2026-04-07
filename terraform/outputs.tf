locals {
  master_ip = split("/", var.k3s_master_ip)[0]
  worker_ips = [for ip in var.k3s_worker_ips : split("/", ip)[0]]
}

output "k3s_master_ip" {
  description = "k3s master node IP address"
  value       = local.master_ip
}

output "k3s_worker_ips" {
  description = "k3s worker nodes IP addresses"
  value       = local.worker_ips
}

output "k3s_ssh_private_key" {
  description = "SSH private key for k3s nodes"
  value       = tls_private_key.k3s.private_key_openssh
  sensitive   = true
}

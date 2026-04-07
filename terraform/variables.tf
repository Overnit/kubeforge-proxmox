variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the format USER@REALM!TOKENID=SECRET"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pvehp"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "k3s_master_count" {
  description = "Number of k3s master nodes"
  type        = number
  default     = 1
}

variable "k3s_worker_count" {
  description = "Number of k3s worker nodes"
  type        = number
  default     = 2
}

variable "k3s_master_cores" {
  type    = number
  default = 4
}

variable "k3s_master_memory" {
  description = "Master memory in MB"
  type        = number
  default     = 8192
}

variable "k3s_worker_cores" {
  type    = number
  default = 4
}

variable "k3s_worker_memory" {
  description = "Worker memory in MB"
  type        = number
  default     = 8192
}

variable "k3s_disk_size" {
  description = "Disk size in GB for k3s nodes"
  type        = number
  default     = 32
}

variable "k3s_datastore_id" {
  description = "Proxmox datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "k3s_network_bridge" {
  description = "Network bridge for VMs"
  type        = string
  default     = "vmbr0"
}

variable "k3s_vm_start_id" {
  description = "Starting VM ID for k3s cluster"
  type        = number
  default     = 200
}

variable "k3s_master_ip" {
  description = "Static IP for k3s master (CIDR notation)"
  type        = string
  default     = "192.168.0.210/24"
}

variable "k3s_worker_ips" {
  description = "Static IPs for k3s workers (CIDR notation)"
  type        = list(string)
  default     = ["192.168.0.211/24", "192.168.0.212/24"]
}

variable "k3s_gateway" {
  description = "Network gateway"
  type        = string
  default     = "192.168.0.1"
}

variable "k3s_dns_server" {
  description = "DNS server"
  type        = string
  default     = "192.168.0.1"
}

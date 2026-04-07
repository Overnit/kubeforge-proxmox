# --- k3s Master ---
resource "proxmox_virtual_environment_vm" "k3s_master" {
  name        = "k3s-master-0"
  description = "k3s master node - Managed by Terraform"
  tags        = ["k3s", "master", "terraform"]

  node_name      = var.proxmox_node
  vm_id          = var.k3s_vm_start_id
  on_boot        = true
  stop_on_destroy = true

  agent {
    enabled = false
  }

  cpu {
    cores = var.k3s_master_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.k3s_master_memory
  }

  disk {
    datastore_id = var.k3s_datastore_id
    import_from  = proxmox_virtual_environment_download_file.ubuntu_2404.id
    interface    = "scsi0"
    discard      = "on"
    size         = var.k3s_disk_size
    ssd          = true
  }

  initialization {
    datastore_id = var.k3s_datastore_id

    dns {
      servers = [var.k3s_dns_server]
    }

    ip_config {
      ipv4 {
        address = var.k3s_master_ip
        gateway = var.k3s_gateway
      }
    }

    user_account {
      keys     = [trimspace(tls_private_key.k3s.public_key_openssh)]
      username = "ubuntu"
    }
  }

  network_device {
    bridge = var.k3s_network_bridge
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [disk[0].import_from]
  }
}

# --- k3s Workers ---
resource "proxmox_virtual_environment_vm" "k3s_worker" {
  count       = var.k3s_worker_count
  name        = "k3s-worker-${count.index}"
  description = "k3s worker node ${count.index} - Managed by Terraform"
  tags        = ["k3s", "worker", "terraform"]

  node_name      = var.proxmox_node
  vm_id          = var.k3s_vm_start_id + 1 + count.index
  on_boot        = true
  stop_on_destroy = true

  agent {
    enabled = false
  }

  cpu {
    cores = var.k3s_worker_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.k3s_worker_memory
  }

  disk {
    datastore_id = var.k3s_datastore_id
    import_from  = proxmox_virtual_environment_download_file.ubuntu_2404.id
    interface    = "scsi0"
    discard      = "on"
    size         = var.k3s_disk_size
    ssd          = true
  }

  initialization {
    datastore_id = var.k3s_datastore_id

    dns {
      servers = [var.k3s_dns_server]
    }

    ip_config {
      ipv4 {
        address = var.k3s_worker_ips[count.index]
        gateway = var.k3s_gateway
      }
    }

    user_account {
      keys     = [trimspace(tls_private_key.k3s.public_key_openssh)]
      username = "ubuntu"
    }
  }

  network_device {
    bridge = var.k3s_network_bridge
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [disk[0].import_from]
  }
}

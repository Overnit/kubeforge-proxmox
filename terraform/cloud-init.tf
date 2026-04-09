# --- SSH Key ---
resource "tls_private_key" "k3s" {
  algorithm = "ED25519"
}

# --- Cloud image ---
resource "proxmox_virtual_environment_download_file" "ubuntu_2404" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.proxmox_node
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
  overwrite    = true
}

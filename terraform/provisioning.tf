resource "local_file" "k3s_ssh_key" {
  content         = tls_private_key.k3s.private_key_openssh
  filename        = "${path.module}/.k3s_ssh_key"
  file_permission = "0600"
}

resource "null_resource" "k3s_setup" {
  depends_on = [
    proxmox_virtual_environment_vm.k3s_master,
    proxmox_virtual_environment_vm.k3s_worker,
    local_file.k3s_ssh_key
  ]

  provisioner "local-exec" {
    command = "bash ../scripts/setup-k3s.sh ${local_file.k3s_ssh_key.filename}"
    environment = {
      MASTER_IP  = split("/", var.k3s_master_ip)[0]
      WORKER_IPS = join(" ", [for ip in var.k3s_worker_ips : split("/", ip)[0]])
    }
  }
}

resource "null_resource" "arc_setup" {
  depends_on = [null_resource.k3s_setup]

  provisioner "local-exec" {
    command = <<EOF
      export KUBECONFIG=~/.kube/k3s-config
      /opt/homebrew/bin/helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
      /opt/homebrew/bin/helm repo update
      
      /opt/homebrew/bin/helm upgrade --install arc \
        --namespace arc-systems --create-namespace \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
        --wait

      /opt/homebrew/bin/helm upgrade --install arc-runner-set \
        --namespace arc-runners --create-namespace \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
        --set githubConfigUrl="${var.github_config_url}" \
        --set githubConfigSecret.github_token="${var.github_pat}" \
        --set minRunners=1 --set maxRunners=5 \
        --wait
EOF
  }
}

#!/usr/bin/env bash
set -euo pipefail

# k3s cluster setup script
# Run from a machine with network access to the VMs (local network)
# Usage: ./setup-k3s.sh [SSH_KEY_PATH]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

SSH_KEY="${1:-}"
MASTER_IP="${MASTER_IP:-$(cd "$TF_DIR" && terraform output -raw k3s_master_ip)}"
WORKER_IPS="${WORKER_IPS:-$(cd "$TF_DIR" && terraform output -json k3s_worker_ips | python3 -c "import sys,json;print(' '.join(json.load(sys.stdin)))")}"

if [[ -z "$SSH_KEY" ]]; then
  SSH_KEY="$(mktemp)"
  (cd "$TF_DIR" && terraform output -raw k3s_ssh_private_key) > "$SSH_KEY"
  chmod 600 "$SSH_KEY"
  TEMP_KEY=true
else
  TEMP_KEY=false
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i $SSH_KEY"
SSH_USER="ubuntu"

echo "=== k3s Cluster Setup ==="
echo "Master: $MASTER_IP"
echo "Workers: $WORKER_IPS"
echo ""

# --- Install k3s server on master ---
echo "[1/3] Installing k3s server on master ($MASTER_IP)..."
# shellcheck disable=SC2029
ssh $SSH_OPTS "$SSH_USER@$MASTER_IP" bash -s <<'MASTER_SCRIPT'
  set -euo pipefail

  # Wait for cloud-init
  cloud-init status --wait 2>/dev/null || true

  # Install prerequisites
  if ! command -v qemu-ga &>/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq qemu-guest-agent curl open-iscsi nfs-common
    sudo systemctl enable --now qemu-guest-agent
  fi

  # Install k3s server
  if ! command -v k3s &>/dev/null; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san $(hostname -I | awk '{print $1}') --write-kubeconfig-mode 644" sh -
    echo "Waiting for k3s to be ready..."
    until kubectl get nodes &>/dev/null; do sleep 2; done
    echo "k3s server is ready!"
  else
    echo "k3s already installed"
  fi
MASTER_SCRIPT

# --- Get join token ---
echo "[2/3] Retrieving join token..."
K3S_TOKEN=$(ssh $SSH_OPTS "$SSH_USER@$MASTER_IP" "sudo cat /var/lib/rancher/k3s/server/node-token")

# --- Install k3s agent on workers ---
echo "[3/3] Installing k3s agent on workers..."
for WORKER_IP in $WORKER_IPS; do
  echo "  → Worker $WORKER_IP..."
  # shellcheck disable=SC2029
  ssh $SSH_OPTS "$SSH_USER@$WORKER_IP" bash -s <<WORKER_SCRIPT
    set -euo pipefail

    cloud-init status --wait 2>/dev/null || true

    if ! command -v qemu-ga &>/dev/null; then
      sudo apt-get update -qq
      sudo apt-get install -y -qq qemu-guest-agent curl open-iscsi nfs-common
      sudo systemctl enable --now qemu-guest-agent
    fi

    if ! command -v k3s &>/dev/null; then
      curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="${K3S_TOKEN}" sh -
      echo "k3s agent started on $WORKER_IP"
    else
      echo "k3s already installed"
    fi
WORKER_SCRIPT
done

echo ""
echo "=== Cluster Ready ==="
echo ""
echo "Get kubeconfig:"
echo "  ssh $SSH_OPTS $SSH_USER@$MASTER_IP 'cat /etc/rancher/k3s/k3s.yaml' | sed 's/127.0.0.1/$MASTER_IP/g' > ~/.kube/k3s-config"
echo "  export KUBECONFIG=~/.kube/k3s-config"
echo "  kubectl get nodes"

if [[ "$TEMP_KEY" == "true" ]]; then
  rm -f "$SSH_KEY"
fi

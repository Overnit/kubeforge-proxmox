# Homelab Proxmox

Infrastructure as Code for provisioning and managing a k3s Kubernetes cluster on Proxmox VE using Terraform.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Proxmox VE Host                   │
│                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ k3s-master-0│  │ k3s-worker-0 │  │k3s-worker-1│ │
│  │ 192.168.0.210│ │ 192.168.0.211│  │192.168.0.212││
│  │  (server)   │  │   (agent)    │  │  (agent)   │ │
│  └─────────────┘  └──────────────┘  └────────────┘ │
└─────────────────────────────────────────────────────┘
         ▲
         │ Cloudflare Access Tunnel
         │
┌────────┴────────┐
│  CF Access Proxy │  ← scripts/cf-access-proxy.py
│  localhost:18006 │
└─────────────────┘
         ▲
         │
┌────────┴────────┐
│    Terraform     │
│   (bpg/proxmox) │
└─────────────────┘
```

## Stack

| Component | Version |
|---|---|
| Proxmox VE | 9.1.1 |
| Terraform | >= 1.5.0 |
| Provider (bpg/proxmox) | ~> 0.78 |
| Ubuntu Cloud Image | 24.04 LTS (Noble) |
| k3s | Latest stable |
| Guest OS | Ubuntu 24.04 (cloud-init) |

## What It Provisions

- **1 k3s master** — control plane node with server role
- **2 k3s workers** — agent nodes joining the cluster
- **SSH key** — auto-generated ED25519 key pair (via `tls_private_key`)
- **Cloud-init** — automated Ubuntu 24.04 VM setup with static IPs
- **QEMU image** — downloads Ubuntu cloud image for VM disk import

## Prerequisites

- Proxmox VE with API token access (see [API Token Setup](#proxmox-api-token))
- Terraform >= 1.5.0
- Python 3 (for CF Access proxy, if behind Cloudflare)
- `kubectl` and `ssh` on your workstation

## Quick Start

### 1. Clone

```bash
git clone https://github.com/Overnit/homelab-proxmox.git
cd homelab-proxmox
```

### 2. Configure

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values
```

### 3. Start CF Access Proxy (if needed)

If your Proxmox is behind Cloudflare Access:

```bash
export CF_ACCESS_CLIENT_ID="your-service-token-id"
export CF_ACCESS_CLIENT_SECRET="your-service-token-secret"
python3 scripts/cf-access-proxy.py
```

This runs a local HTTPS reverse proxy on `localhost:18006` that injects CF Access headers into every request forwarded to your Proxmox host.

### 4. Deploy VMs

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 5. Install k3s

```bash
# Export the SSH key
cd terraform && terraform output -raw k3s_ssh_private_key > /tmp/k3s-key && chmod 600 /tmp/k3s-key
cd ..

# Run the k3s installer
bash scripts/setup-k3s.sh /tmp/k3s-key
```

### 6. Get Kubeconfig

```bash
ssh -i /tmp/k3s-key ubuntu@192.168.0.210 'cat /etc/rancher/k3s/k3s.yaml' \
  | sed 's/127.0.0.1/192.168.0.210/g' > ~/.kube/k3s-config

export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

## Project Structure

```
homelab_proxmox/
├── .gitignore
├── README.md
├── .instructions.md              # AI coding instructions
├── terraform/
│   ├── versions.tf               # Required providers and versions
│   ├── main.tf                   # Proxmox provider config
│   ├── variables.tf              # All input variables with defaults
│   ├── cloud-init.tf             # SSH key + Ubuntu cloud image download
│   ├── k3s-cluster.tf            # Master + worker VM resources
│   ├── outputs.tf                # IPs and SSH key outputs
│   ├── terraform.tfvars.example  # Template for secrets
│   └── terraform.tfvars          # Your secrets (git-ignored)
└── scripts/
    ├── cf-access-proxy.py        # Cloudflare Access HTTPS reverse proxy
    └── setup-k3s.sh              # Automated k3s cluster installer
```

## Configuration Reference

### Terraform Variables

| Variable | Default | Description |
|---|---|---|
| `proxmox_endpoint` | — | Proxmox API URL (e.g. `https://localhost:18006`) |
| `proxmox_api_token` | — | API token `USER@REALM!TOKENID=SECRET` |
| `proxmox_node` | `pvehp` | Proxmox node name |
| `k3s_master_count` | `1` | Number of master nodes |
| `k3s_worker_count` | `2` | Number of worker nodes |
| `k3s_master_cores` | `4` | CPU cores per master |
| `k3s_master_memory` | `8192` | RAM (MB) per master |
| `k3s_worker_cores` | `4` | CPU cores per worker |
| `k3s_worker_memory` | `8192` | RAM (MB) per worker |
| `k3s_disk_size` | `32` | Disk size (GB) per node |
| `k3s_master_ip` | `192.168.0.210/24` | Master static IP (CIDR) |
| `k3s_worker_ips` | `[211, 212]/24` | Worker static IPs (CIDR) |
| `k3s_gateway` | `192.168.0.1` | Network gateway |
| `k3s_dns_server` | `192.168.0.1` | DNS server |
| `k3s_datastore_id` | `local-lvm` | Proxmox storage pool |
| `k3s_network_bridge` | `vmbr0` | Network bridge |
| `k3s_vm_start_id` | `200` | Starting VM ID |

### Terraform Outputs

| Output | Description |
|---|---|
| `k3s_master_ip` | Master node IP address |
| `k3s_worker_ips` | List of worker node IPs |
| `k3s_ssh_private_key` | SSH private key (sensitive) |

## Proxmox API Token

Create an API token in Proxmox:

1. Go to **Datacenter → Permissions → API Tokens**
2. Create token for `root@pam` (or a dedicated user)
3. **Uncheck** "Privilege Separation" for full access
4. Copy the token in format: `root@pam!tokenname=secret-uuid`

## Cloudflare Access Proxy

If your Proxmox is exposed via Cloudflare Tunnel with Zero Trust access policies, the included Python proxy (`scripts/cf-access-proxy.py`) handles authentication transparently.

**How it works:**
1. Generates a self-signed cert for `localhost`
2. Listens on `https://localhost:18006`
3. Forwards all requests to your Proxmox host
4. Injects `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers

**Environment variables:**

| Variable | Description |
|---|---|
| `CF_ACCESS_CLIENT_ID` | Cloudflare Access Service Token ID |
| `CF_ACCESS_CLIENT_SECRET` | Cloudflare Access Service Token Secret |
| `UPSTREAM_URL` | Proxmox URL (default: `https://proxmox.overnit.com`) |
| `LISTEN_PORT` | Local port (default: `18006`) |

## Post-Deployment

After k3s is running, you can install [Actions Runner Controller (ARC)](https://github.com/actions/actions-runner-controller) for self-hosted GitHub Actions runners:

```bash
export KUBECONFIG=~/.kube/k3s-config

# Install ARC controller
helm install arc \
  --namespace arc-systems --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

# Install runner scale set (repo-level)
helm install arc-runner-set \
  --namespace arc-runners --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --set githubConfigUrl="https://github.com/YOUR_ORG/YOUR_REPO" \
  --set githubConfigSecret.github_token="ghp_YOUR_PAT" \
  --set minRunners=1 --set maxRunners=5
```

## Teardown

```bash
cd terraform
terraform destroy
```

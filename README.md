# KubeForge Proxmox

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
git clone https://github.com/Overnit/kubeforge-proxmox.git
cd kubeforge-proxmox
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

### 5. Automation Magic

With the new `provisioning.tf` logic, Terraform automatically triggers `setup-k3s.sh` internally, installs the entire Kubernetes Core, syncs the Helm charts, and authenticates ARC against your GitHub environment directly upon complete boot sequence!

You don't need to manually run post-deployment scripts anymore!

### 6. Get Kubeconfig

The kubeconfig is automatically injected into your user directory `~/.kube/k3s-config` natively by the local-exec provisioners.

```bash
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

## Project Structure

```
kubeforge_proxmox/
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

All Post-Deployment ARC configurations for self-hosted GitHub Actions runners are now natively integrated. `terraform apply` will automatically inject Helm and boot up the Action Runner Controller based on the parameters (`github_config_url` and `github_pat`) in your `terraform.tfvars`.

## Teardown

```bash
cd terraform
terraform destroy
```

## Secrets Inventory

All tokens and credentials used across the infrastructure. **Never commit actual values.**

### Proxmox

| Secret | Format | Where to create | Used in |
|---|---|---|---|
| Proxmox API Token | `root@pam!tokenname=uuid` | Proxmox → Datacenter → Permissions → API Tokens | `terraform.tfvars` → `proxmox_api_token` |

### Cloudflare

| Secret | Where to create | Used in |
|---|---|---|
| CF Access Service Token ID | [Zero Trust → Access → Service Auth](https://one.dash.cloudflare.com/) → Service Tokens | `CF_ACCESS_CLIENT_ID` env var for `cf-access-proxy.py` |
| CF Access Service Token Secret | Same as above (shown once on creation) | `CF_ACCESS_CLIENT_SECRET` env var for `cf-access-proxy.py` |
| CF API Token | [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens) | GitHub org secret `CLOUDFLARE_API_TOKEN` |
| CF Account ID | Cloudflare dashboard → any domain → Overview sidebar | GitHub org secret `CLOUDFLARE_ACCOUNT_ID` |
| CF Zone ID | Cloudflare dashboard → domain → Overview sidebar | GitHub org secret `CLOUDFLARE_ZONE_ID` |

**CF API Token permissions required:**

| Permission | Scope | Used for |
|---|---|---|
| Zone → DNS → Edit | overnit.com | Workers custom domains, DNS record management |
| Account → Cloudflare Pages → Edit | All accounts | Legacy (can be removed if not using Pages) |
| Account → Workers Scripts → Edit | All accounts | Deploying Workers via `wrangler deploy` |
| Zone → Workers Routes → Edit | overnit.com | Binding Workers to custom domain routes |

### GitHub

| Secret | Where to create | Used in |
|---|---|---|
| GitHub PAT (Classic) | [github.com/settings/tokens](https://github.com/settings/tokens) | ARC runner-set helm install (`githubConfigSecret.github_token`) |

**GitHub PAT scopes required:** `repo`, `workflow`, `admin:org`

### GitHub Org Secrets (Overnit)

Configured at [github.com/organizations/Overnit/settings/secrets/actions](https://github.com/organizations/Overnit/settings/secrets/actions):

| Secret Name | Source | Used by |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | CF API Token (see above) | `landing-page` deploy workflow |
| `CLOUDFLARE_ACCOUNT_ID` | CF Account ID | `landing-page` deploy workflow |
| `CLOUDFLARE_ZONE_ID` | CF Zone ID | `landing-page` deploy workflow (DNS cleanup) |

### Where Secrets Live at Runtime

| Location | Secrets stored |
|---|---|
| `terraform.tfvars` (git-ignored) | Proxmox API token, endpoint |
| Environment variables (shell) | CF Access service token ID/secret |
| GitHub org secrets | CF API token, account ID, zone ID |
| Kubernetes secret (arc-runners ns) | GitHub PAT for ARC |
| `~/.kube/k3s-config` (local file) | k3s kubeconfig with cluster certs |

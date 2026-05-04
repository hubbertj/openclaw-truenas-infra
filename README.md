# OpenClaw TrueNAS Infrastructure

Infrastructure as Code (IaC) for deploying [OpenClaw](https://openclaw.ai/) on a dedicated Ubuntu VM hosted by TrueNAS, with Amazon Bedrock integration.

## Overview

This repository uses Terraform to:

1. **Provision AWS Resources** — Creates an IAM user with `AmazonBedrockFullAccess` and generates access keys.
2. **Configure the OpenClaw VM** — SSHs into the Ubuntu VM, applies OpenClaw config (Bedrock provider, media models, gateway bind), writes credentials to `~/.openclaw/openclaw.env`, and ensures the systemd service is running.
3. **Set up HTTPS** — Installs nginx with a mkcert self-signed certificate on the VM, proxying `https://10.0.0.60/` → `http://localhost:18789`.
4. **Configure TrueNAS networking** — Verifies connectivity between the VM and TrueNAS services via an internal bridge.
5. **Sync GitHub Secrets** — Optionally pushes Bedrock credentials to GitHub repository secrets.

## Infrastructure

| Component | Details |
|---|---|
| OpenClaw VM | Ubuntu 24.04, `10.0.0.60`, TrueNAS VM ID 21 |
| TrueNAS host | `10.0.0.160` (bond123 LACP), backup port `10.0.1.160` (eno4) |
| Internal bridge | `br0` on TrueNAS — `172.16.100.1/24` (VM uses `172.16.100.2`) |
| Cisco switch | `10.0.0.200` (HTTPS management only) |
| AWS account | `914713788242` (profile: `aws-openclaw-ai`) |

## Network Architecture

The OpenClaw VM's primary NIC (`ens3`) is attached to TrueNAS's `bond123` via **macvtap**. This is a kernel-level limitation: a VM using macvtap on a physical interface **cannot communicate with the TrueNAS host's own IP** (`10.0.0.160`) through that interface. This is permanent and not fixable via firewall rules.

**Workaround:** A second NIC (`ens4`) connects the VM to `br0`, a dedicated Linux bridge on TrueNAS with no physical members. All OpenClaw → TrueNAS communication uses this internal bridge:

```
OpenClaw VM (ens4: 172.16.100.2)
        ↕  sub-ms latency
TrueNAS br0 (172.16.100.1)
        ↕  host-local
TrueNAS services (qBittorrent :10000, API :80/:443, SSH :22)
```

`ping 10.0.0.160` from the VM will always fail — this is expected. `ping 172.16.100.1` should always succeed.

## Prerequisites

- **AWS CLI** configured with an SSO profile named `aws-openclaw-ai`
- **Terraform** 1.5+
- **S3 bucket** `openclaw-truenas-infra-tfstate-914713788242` (already exists)
- **SSH key** for `openclaw@10.0.0.60` (passwordless)

## Deployment

### 1. Authenticate AWS

```bash
aws sso login --profile aws-openclaw-ai
```

### 2. Set required secrets

```bash
export TF_VAR_truenas_password="Admin1"
export TF_VAR_openclaw_vm_password="admin1"
export TF_VAR_qbittorrent_password="admin1"
export TF_VAR_github_pat="ghp_..."       # optional — configures GitHub MCP in OpenClaw
export TF_VAR_github_token="ghp_..."     # optional — syncs keys to GitHub Secrets
```

### 3. Apply

```bash
cd terraform
terraform init
terraform apply
```

## Accessing OpenClaw

- **HTTPS:** `https://10.0.0.60/`
- **HTTP (direct):** `http://10.0.0.60:18789/`

### Trust the self-signed certificate on Mac

```bash
scp openclaw@10.0.0.60:/etc/ssl/openclaw/rootCA.pem ~/Downloads/openclaw-rootCA.pem
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/openclaw-rootCA.pem
```

## Amazon Bedrock Models

The following cross-region inference profile IDs are configured (Claude 4.x requires `us.*` prefix):

| Model | ID |
|---|---|
| Claude Opus 4.7 | `us.anthropic.claude-opus-4-7` |
| Claude Sonnet 4.6 | `us.anthropic.claude-sonnet-4-6` |
| Claude Opus 4.5 | `us.anthropic.claude-opus-4-5-20251101-v1:0` |
| Claude Sonnet 4.5 | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` |

Media understanding (image/video) uses `us.anthropic.claude-haiku-4-5-20251001-v1:0` via the `amazon-bedrock` provider.

## Secret Management

If `TF_VAR_github_token` is set, Terraform syncs these to GitHub repository secrets:

- `BEDROCK_ACCESS_KEY_ID`
- `BEDROCK_SECRET_ACCESS_KEY`

## Troubleshooting

### OpenClaw not reachable

```bash
# Check service status
ssh openclaw@10.0.0.60 "XDG_RUNTIME_DIR=/run/user/1000 systemctl --user status openclaw-gateway"

# Check health endpoint
curl -sf http://10.0.0.60:18789/health

# Tail logs
ssh openclaw@10.0.0.60 "XDG_RUNTIME_DIR=/run/user/1000 journalctl --user -u openclaw-gateway -f"
```

### TrueNAS services unreachable from VM

```bash
ssh openclaw@10.0.0.60 "ping -c 3 172.16.100.1"        # bridge — should always work
ssh openclaw@10.0.0.60 "ping -c 3 10.0.0.160"          # macvtap — always fails, expected
ssh openclaw@10.0.0.60 "curl -sf http://172.16.100.1:10000/api/v2/app/webapiVersion"
```

If `172.16.100.1` is unreachable, the `br0` interface on TrueNAS may have been lost after a reboot. Recreate it via the TrueNAS UI (Network → Interfaces → Add Bridge) with IP `172.16.100.1/24` and no members, then re-run `terraform apply` to reprovision the VM NIC.

### Config file location

```
/home/openclaw/.openclaw/openclaw.json       # OpenClaw config
/home/openclaw/.openclaw/openclaw.env        # AWS + TrueNAS credentials
~/.config/systemd/user/openclaw-gateway.service
/etc/netplan/99-internal-bridge.yaml         # ens4 static IP config
```

### Cisco switch

Management UI: `https://10.0.0.200` (HTTPS only, no SSH/Telnet)  
Credentials: `admin` / `Firewall102!A`

## License

MIT

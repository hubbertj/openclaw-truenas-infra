# Network Routing Configuration

## Problem
OpenClaw VM (10.0.0.60) cannot reach TrueNAS server (10.0.0.160) or its applications like qBittorrent.

## Solution
Configure TrueNAS firewall and network settings to allow traffic from OpenClaw VM.

## Prerequisites
- Both VMs on same subnet: 10.0.0.0/24
- Hypervisor networking bridge configured (usually automatic)
- TrueNAS firewall needs explicit allow rules

## Implementation Steps

### 1. Verify Hypervisor Network Bridge
On the hypervisor/TrueNAS host:
```bash
# Check if both VMs can reach the gateway
ping 10.0.0.1

# Verify both VMs are on the same bridge
ip link show | grep -i bridge
```

### 2. TrueNAS Firewall Configuration
SSH to TrueNAS root and run:
```bash
# Allow traffic from OpenClaw VM to TrueNAS
ufw allow from 10.0.0.60 to 10.0.0.160
ufw allow from 10.0.0.60 to 10.0.0.160 port 10000  # qBittorrent

# Allow SSH from OpenClaw VM
ufw allow from 10.0.0.60 to 10.0.0.160 port 22

# Reload firewall
ufw reload

# Verify rules
ufw status
```

### 3. Verify Connectivity
From OpenClaw VM:
```bash
# Test basic connectivity
ping 10.0.0.160

# Test qBittorrent API
curl http://10.0.0.160:10000/api/v2/app/webapiVersion

# Test SSH
ssh root@10.0.0.160
```

### 4. TrueNAS qBittorrent App Network Configuration
In TrueNAS UI:
1. Go to Apps → qBittorrent
2. Verify it's bound to `0.0.0.0:10000` (not localhost-only)
3. Check network settings allow external connections

## Terraform Integration
Once verified, add to `terraform/truenas.tf`:
```hcl
resource "null_resource" "configure_truenas_firewall" {
  triggers = {
    openclaw_vm_ip = var.openclaw_vm_host
    truenas_host   = var.truenas_host
  }

  connection {
    type     = "ssh"
    host     = var.truenas_host
    user     = "root"
    password = var.truenas_password
  }

  provisioner "remote-exec" {
    inline = [
      "ufw allow from ${var.openclaw_vm_host} to ${var.truenas_host}",
      "ufw allow from ${var.openclaw_vm_host} to ${var.truenas_host} port 10000",
      "ufw allow from ${var.openclaw_vm_host} to ${var.truenas_host} port 22",
      "ufw reload",
    ]
  }
}
```

## Troubleshooting

### If ping fails:
- Check hypervisor bridge configuration
- Verify both VMs are on same network
- Check VLAN settings if applicable

### If qBittorrent API fails:
- Verify qBittorrent is running: `docker ps | grep qbittorrent`
- Check TrueNAS firewall: `ufw status`
- Verify port forwarding: `netstat -tlnp | grep 10000`

### If SSH fails:
- Verify SSH service running on TrueNAS: `systemctl status ssh`
- Check firewall rules: `ufw status verbose`
- Test with root password

## Related Documentation
- TrueNAS UFW: https://www.truenas.com/docs/
- qBittorrent API: https://github.com/qbittorrent/qBittorrent/wiki/Web-API

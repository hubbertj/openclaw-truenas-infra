# TrueNAS Firewall and Network Configuration

resource "null_resource" "configure_truenas_firewall" {
  triggers = {
    openclaw_vm_ip = var.openclaw_vm_host
    truenas_host   = var.truenas_host
    script_hash    = filemd5("${path.module}/truenas.tf")
  }

  connection {
    type     = "ssh"
    host     = var.truenas_host
    user     = "root"
    password = var.truenas_password
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      /bin/sh <<'FIREWALLSCRIPT'
      set -euo pipefail
      
      echo "==> [$(date)] Configuring TrueNAS firewall for OpenClaw VM..."
      
      OPENCLAW_IP="${var.openclaw_vm_host}"
      TRUENAS_IP="${var.truenas_host}"
      
      # Check if ufw is installed
      if ! command -v ufw &> /dev/null; then
        echo "WARN: ufw not found, skipping firewall configuration"
        exit 0
      fi
      
      # Enable UFW if not already enabled
      ufw --force enable || true
      
      # Allow traffic from OpenClaw VM to TrueNAS
      echo "==> Allowing traffic from $OPENCLAW_IP to $TRUENAS_IP..."
      ufw allow from "$OPENCLAW_IP" to "$TRUENAS_IP" comment "Allow OpenClaw VM" || true
      
      # Allow qBittorrent API port
      echo "==> Allowing qBittorrent API access from $OPENCLAW_IP..."
      ufw allow from "$OPENCLAW_IP" to "$TRUENAS_IP" port 10000 proto tcp comment "Allow qBittorrent from OpenClaw" || true
      
      # Allow SSH from OpenClaw VM
      echo "==> Allowing SSH access from $OPENCLAW_IP..."
      ufw allow from "$OPENCLAW_IP" to "$TRUENAS_IP" port 22 proto tcp comment "Allow SSH from OpenClaw" || true
      
      # Reload firewall
      echo "==> Reloading firewall rules..."
      ufw reload || true
      
      # Verify rules
      echo "==> Current firewall status:"
      ufw status | grep -E "^$OPENCLAW_IP|^10.0.0" || true
      
      echo "==> [$(date)] Firewall configuration complete"
FIREWALLSCRIPT
EOF
    ]
  }
}

# Test network connectivity
resource "null_resource" "test_network_connectivity" {
  depends_on = [null_resource.configure_truenas_firewall]

  triggers = {
    openclaw_vm_ip = var.openclaw_vm_host
    truenas_host   = var.truenas_host
  }

  connection {
    type     = "ssh"
    host     = var.openclaw_vm_host
    user     = var.openclaw_vm_user
    password = var.openclaw_vm_password
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      /bin/sh <<'TESTSCRIPT'
      set -euo pipefail
      
      echo "==> [$(date)] Testing network connectivity to TrueNAS..."
      
      TRUENAS_IP="${var.truenas_host}"
      QBITTORRENT_PORT="10000"
      
      # Test ping
      echo "==> Testing ping to TrueNAS ($TRUENAS_IP)..."
      if ping -c 3 "$TRUENAS_IP" &> /dev/null; then
        echo "✓ Ping successful"
      else
        echo "✗ Ping failed"
        exit 1
      fi
      
      # Test qBittorrent API
      echo "==> Testing qBittorrent API connectivity..."
      if timeout 10 curl -sf "http://$TRUENAS_IP:$QBITTORRENT_PORT/api/v2/app/webapiVersion" > /dev/null; then
        echo "✓ qBittorrent API accessible"
      else
        echo "⚠ qBittorrent API not responding (may need container restart)"
      fi
      
      # Test SSH
      echo "==> Testing SSH connectivity..."
      if timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$TRUENAS_IP" "echo 'SSH connection successful'" &> /dev/null; then
        echo "✓ SSH connection successful"
      else
        echo "⚠ SSH connection failed (verify credentials)"
      fi
      
      echo "==> [$(date)] Connectivity tests complete"
TESTSCRIPT
EOF
    ]
  }
}

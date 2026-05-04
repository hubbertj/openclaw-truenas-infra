# Configuration and deployment for the dedicated OpenClaw VM.
# This replaces the TrueNAS App deployment pattern with a native VM installation.

resource "null_resource" "openclaw_vm_config" {
  triggers = {
    # Re-run if the Bedrock config, connection info, or the script itself changes
    bedrock_config_hash = sha256(jsonencode(local.bedrock_config))
    vm_host             = var.openclaw_vm_host
    access_key_id       = aws_iam_access_key.openclaw_bedrock.id
    script_hash         = filemd5("${path.module}/openclaw_vm.tf")
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
      # Use bash for the entire block
      bash <<'REMOTESCRIPT'
      set -euo pipefail
      
      # Redirect output for debugging
      exec > >(tee -a /tmp/openclaw_deploy.log) 2>&1
      echo "==> [$(date)] Starting configuration update..."

      # Variables from Terraform
      VM_PASSWORD='${var.openclaw_vm_password}'
      VM_USER='${var.openclaw_vm_user}'
      AWS_REGION='${var.aws_region}'
      AWS_KEY_ID='${aws_iam_access_key.openclaw_bedrock.id}'
      AWS_KEY_SECRET='${aws_iam_access_key.openclaw_bedrock.secret}'

      run_sudo() {
        echo "$VM_PASSWORD" | sudo -S -E "$@"
      }

      export DEBIAN_FRONTEND=noninteractive

      # Ensure environment for systemctl --user
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
      
      # Ensure OpenClaw is in PATH
      export PATH="$PATH:$(npm config get prefix)/bin"

      echo "==> Initializing OpenClaw if needed..."
      if [ ! -d "$HOME/.openclaw" ]; then
        openclaw onboard --non-interactive --accept-risk --mode local --install-daemon || true
      fi

      echo "==> Applying configuration via OpenClaw CLI..."
      openclaw config set gateway.bind lan
      openclaw config set gateway.controlUi.allowedOrigins '["*"]'

      echo "==> Resetting and injecting Bedrock provider config..."
      # Delete existing to clear any stale/invalid state
      openclaw config delete models.providers.amazon-bedrock || true
      openclaw config delete plugins.entries.amazon-bedrock || true

      # Claude 4.x on Bedrock requires cross-region inference profile IDs (us.*), not direct model IDs.
      openclaw config set models.providers.amazon-bedrock '{baseUrl: "https://bedrock-runtime.us-east-1.amazonaws.com", api: "bedrock-converse-stream", auth: "aws-sdk", models: ["us.anthropic.claude-opus-4-7", "us.anthropic.claude-sonnet-4-6", "us.anthropic.claude-opus-4-5-20251101-v1:0", "us.anthropic.claude-sonnet-4-5-20250929-v1:0"]}'
      openclaw config set plugins.entries.amazon-bedrock '{enabled: true, config: {discovery: {enabled: true, region: "us-east-1"}}}'

      echo "==> Setting up AWS environment file..."
      mkdir -p "$HOME/.openclaw"
      cat <<EON > "$HOME/.openclaw/openclaw.env"
AWS_ACCESS_KEY_ID=$AWS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_KEY_SECRET
AWS_REGION=$AWS_REGION
EON

      echo "==> Ensuring systemd service is correctly configured..."
      SERVICE_FILE="$HOME/.config/systemd/user/openclaw-gateway.service"
      
      if [ -f "$SERVICE_FILE" ]; then
        if ! grep -q "EnvironmentFile" "$SERVICE_FILE"; then
          sed -i "/\[Service\]/a EnvironmentFile=$HOME/.openclaw/openclaw.env" "$SERVICE_FILE"
        fi
        # Fix bind in service file
        sed -i 's/--bind [^ ]*/--bind lan/g' "$SERVICE_FILE"
        
        systemctl --user daemon-reload
        systemctl --user restart openclaw-gateway
      else
        echo "WARN: service file not found. Restarting gateway manually..."
        openclaw gateway restart || openclaw gateway start || true
      fi

      echo "==> Waiting for OpenClaw to become reachable..."
      for i in {1..20}; do
        if curl -sf http://localhost:18789/health > /dev/null 2>&1; then
          echo "==> [$(date)] OpenClaw is up and healthy."
          exit 0
        fi
        sleep 5
      done

      echo "ERROR: OpenClaw health check failed."
      exit 1
REMOTESCRIPT
EOF
    ]
  }
}

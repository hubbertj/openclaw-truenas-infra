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
      GITHUB_PAT='${var.github_pat}'

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
      # Clear any stale/invalid state before re-applying
      openclaw config unset models.providers.amazon-bedrock || true
      openclaw config unset plugins.entries.amazon-bedrock || true

      # Claude 4.x on Bedrock requires cross-region inference profile IDs (us.*), not direct model IDs.
      # Models must be objects {id, name} — plain strings fail schema validation since OpenClaw 2026.5.x.
      openclaw config set models.providers.amazon-bedrock '{baseUrl: "https://bedrock-runtime.us-east-1.amazonaws.com", api: "bedrock-converse-stream", auth: "aws-sdk", models: [{id: "us.anthropic.claude-opus-4-7", name: "Claude Opus 4.7"}, {id: "us.anthropic.claude-sonnet-4-6", name: "Claude Sonnet 4.6"}, {id: "us.anthropic.claude-opus-4-5-20251101-v1:0", name: "Claude Opus 4.5"}, {id: "us.anthropic.claude-sonnet-4-5-20250929-v1:0", name: "Claude Sonnet 4.5"}]}'
      
      echo "==> Configuring GitHub MCP if PAT is provided..."
      
      echo "==> Configuring media understanding for image/video..."
      openclaw config set tools.media.models '[{id: "amazon-bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0", capabilities: ["image", "video"]}]'
      if [ -n "$GITHUB_PAT" ]; then
        openclaw config set mcp.servers.github '{command: "npx", args: ["@modelcontextprotocol/server-github"], env: {GITHUB_PERSONAL_ACCESS_TOKEN: "'$GITHUB_PAT'"}}'  
      else
        echo "WARN: GITHUB_PAT not provided, skipping GitHub MCP configuration."
      fi
      openclaw config set plugins.entries.amazon-bedrock '{enabled: true, config: {discovery: {enabled: true, region: "us-east-1"}}}'

      echo "==> Setting up AWS environment file..."
      mkdir -p "$HOME/.openclaw"
      cat <<EON > "$HOME/.openclaw/openclaw.env"
AWS_ACCESS_KEY_ID=$AWS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_KEY_SECRET
AWS_REGION=$AWS_REGION
GITHUB_PERSONAL_ACCESS_TOKEN=$GITHUB_PAT
TRUENAS_HOST=10.0.0.160
TRUENAS_USERNAME=root
TRUENAS_PASSWORD=Admin1
QBITTORRENT_HOST=http://10.0.0.160:10000
QBITTORRENT_USERNAME=hubbertj
QBITTORRENT_PASSWORD=admin1
MEDIA_MOVIES_PATH=/mnt/WB-RAID-Z-18TB/movies/
MEDIA_TV_PATH=/mnt/WB-RAID-Z-18TB/tv/
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

resource "null_resource" "openclaw_vm_nginx" {
  depends_on = [null_resource.openclaw_vm_config]

  triggers = {
    vm_host     = var.openclaw_vm_host
    script_hash = filemd5("${path.module}/openclaw_vm.tf")
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
      bash <<'REMOTESCRIPT'
      set -euo pipefail
      exec > >(tee -a /tmp/openclaw_nginx_deploy.log) 2>&1
      echo "==> [$(date)] Starting nginx/TLS setup..."

      VM_PASSWORD='${var.openclaw_vm_password}'

      run_sudo() {
        echo "$VM_PASSWORD" | sudo -S -E "$@"
      }

      export DEBIAN_FRONTEND=noninteractive

      # Step 1 — Install packages
      run_sudo apt-get update -qq
      run_sudo apt-get install -y nginx libnss3-tools

      # Step 2 — Install mkcert (idempotent)
      if [ ! -f /usr/local/bin/mkcert ]; then
        curl -fsSL "https://dl.filippo.io/mkcert/latest?for=linux/amd64" -o /tmp/mkcert
        chmod +x /tmp/mkcert
        run_sudo mv /tmp/mkcert /usr/local/bin/mkcert
      fi

      # Step 3 — Generate local CA and certificate
      run_sudo mkdir -p /etc/ssl/openclaw
      run_sudo env CAROOT=/etc/ssl/openclaw mkcert -install
      run_sudo env CAROOT=/etc/ssl/openclaw mkcert \
        -cert-file /etc/ssl/openclaw/cert.pem \
        -key-file  /etc/ssl/openclaw/key.pem \
        10.0.0.60 localhost
      run_sudo chmod 644 /etc/ssl/openclaw/cert.pem
      run_sudo chmod 600 /etc/ssl/openclaw/key.pem

      # Step 4 — Write nginx config via temp file
      cat <<'NGINXCONF' > /tmp/openclaw_nginx.conf
server {
    listen 443 ssl;
    server_name 10.0.0.60 localhost;

    ssl_certificate     /etc/ssl/openclaw/cert.pem;
    ssl_certificate_key /etc/ssl/openclaw/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass         http://localhost:18789;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_read_timeout 86400;
    }
}

server {
    listen 80;
    server_name 10.0.0.60 localhost;
    return 301 https://$host$request_uri;
}
NGINXCONF

      run_sudo cp /tmp/openclaw_nginx.conf /etc/nginx/sites-available/openclaw
      run_sudo chmod 644 /etc/nginx/sites-available/openclaw
      rm /tmp/openclaw_nginx.conf

      # Step 5 — Enable and start nginx
      run_sudo ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/openclaw
      run_sudo rm -f /etc/nginx/sites-enabled/default
      run_sudo nginx -t
      run_sudo systemctl enable nginx
      run_sudo systemctl restart nginx

      # Step 6 — Health check
      for i in {1..12}; do
        if curl -sf https://10.0.0.60/ > /dev/null 2>&1; then
          echo "==> HTTPS is up."
          exit 0
        fi
        sleep 5
      done
      echo "ERROR: HTTPS health check timed out."
      journalctl -u nginx --no-pager -n 20 || true
      exit 1
REMOTESCRIPT
EOF
    ]
  }
}

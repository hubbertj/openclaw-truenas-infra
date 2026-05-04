locals {
  # Note: The OpenClaw TrueNAS app is being decommissioned in favor of the dedicated VM.
  # These resources are kept here but disabled/commented to prevent errors during transition.
  openclaw_config_path = "/mnt/.ix-apps/app_mounts/openclaw/config/.openclaw/openclaw.json"
}

/*
# Step 1: Deep-merge Bedrock provider config into openclaw.json.
resource "null_resource" "openclaw_json_config" {
  triggers = {
    bedrock_config_hash = sha256(jsonencode(local.bedrock_config))
    script_hash         = sha256(file("${path.module}/truenas.tf"))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      TRUENAS_HOST     = var.truenas_host
      TRUENAS_PASSWORD = local.effective_truenas_password
    }
    command = <<-EOT
      set -euo pipefail
      # ... (omitted)
    EOT
  }
}

# Step 2: Inject AWS credentials as container env vars via the TrueNAS app update API.
resource "null_resource" "openclaw_env_vars" {
  depends_on = [null_resource.openclaw_json_config]

  triggers = {
    access_key_id = aws_iam_access_key.openclaw_bedrock.id
    script_hash   = sha256(file("${path.module}/truenas.tf"))
  }

  provisioner "local-exec" {
    # ... (omitted)
  }
}
*/

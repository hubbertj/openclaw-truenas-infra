locals {
  openclaw_config_path = "/mnt/.ix-apps/app_mounts/openclaw/config/.openclaw/openclaw.json"

  bedrock_config = {
    models = {
      providers = {
        "amazon-bedrock" = {
          baseUrl = "https://bedrock-runtime.us-east-1.amazonaws.com"
          api     = "bedrock-converse-stream"
          auth    = "aws-sdk"
          models  = ["anthropic.claude-3-5-sonnet-20241022-v2:0"]
        }
        "bedrock" = {
          baseUrl = "https://bedrock-runtime.us-east-1.amazonaws.com"
          api     = "bedrock-converse-stream"
          auth    = "aws-sdk"
          models  = ["anthropic.claude-3-5-sonnet-20241022-v2:0"]
        }
      }
    }
    plugins = {
      entries = {
        "amazon-bedrock" = {
          enabled = true
          config = {
            discovery = {
              enabled = true
              region  = "us-east-1"
            }
          }
        }
        "bedrock" = {
          enabled = true
          config = {
            discovery = {
              enabled = true
              region  = "us-east-1"
            }
          }
        }
      }
    }
  }
}

# Step 1: Deep-merge Bedrock provider config into openclaw.json.
# Reads the current file, merges in the bedrock_config block, writes it back.
# Only re-runs if the bedrock config content changes.
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

      CONFIG_PATH="${local.openclaw_config_path}"
      PATCH='${jsonencode(local.bedrock_config)}'

      echo "==> Reading current openclaw.json from TrueNAS..."
      curl -sf -u "root:$TRUENAS_PASSWORD" \
        -X POST "http://$TRUENAS_HOST/api/v2.0/filesystem/get" \
        -H "Content-Type: application/json" \
        -d "\"$CONFIG_PATH\"" \
        > /tmp/openclaw_current.json

      echo "==> Merging Bedrock config (existing keys preserved)..."
      jq --argjson patch "$PATCH" '. * $patch' /tmp/openclaw_current.json \
        > /tmp/openclaw_merged.json

      echo "==> Writing merged config back to TrueNAS via SSH (more reliable for this path)..."
      sshpass -p "$TRUENAS_PASSWORD" scp -o StrictHostKeyChecking=no /tmp/openclaw_merged.json "root@$TRUENAS_HOST:/mnt/.ix-apps/app_mounts/openclaw/config/.openclaw/openclaw.json"

      echo "==> openclaw.json updated."
    EOT
  }
}

# Step 2: Inject AWS credentials as container env vars via the TrueNAS app update API.
# PUT /app/id/openclaw triggers an app redeploy, which picks up the new openclaw.json
# written in step 1. Polls until the job completes, then health-checks the app.
# Re-runs whenever the IAM access key ID changes (i.e. on key rotation).
resource "null_resource" "openclaw_env_vars" {
  depends_on = [null_resource.openclaw_json_config]

  triggers = {
    access_key_id = aws_iam_access_key.openclaw_bedrock.id
    script_hash   = sha256(file("${path.module}/truenas.tf"))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      TRUENAS_HOST     = var.truenas_host
      TRUENAS_PASSWORD = local.effective_truenas_password
      AWS_KEY_ID       = aws_iam_access_key.openclaw_bedrock.id
      AWS_KEY_SECRET   = aws_iam_access_key.openclaw_bedrock.secret
    }
    command = <<-EOT
      set -euo pipefail

      echo "==> Building app update payload..."
      BODY=$(jq -n \
        --arg key_id     "$AWS_KEY_ID" \
        --arg key_secret "$AWS_KEY_SECRET" \
        '{
          values: {
            openclaw: {
              additional_envs: [
                {name: "AWS_ACCESS_KEY_ID",     value: $key_id},
                {name: "AWS_SECRET_ACCESS_KEY", value: $key_secret},
                {name: "AWS_REGION",            value: "us-east-1"}
              ]
            }
          }
        }')

      echo "==> Submitting app update to inject env vars..."
      JOB_ID=$(curl -sf -u "root:$TRUENAS_PASSWORD" \
        -X PUT "http://$TRUENAS_HOST/api/v2.0/app/id/openclaw" \
        -H "Content-Type: application/json" \
        -d "$BODY")
      echo "    Job ID: $JOB_ID"

      echo "==> Polling for job completion (max 150s)..."
      STATE="RUNNING"
      for i in $(seq 1 30); do
        STATE=$(curl -sf -u "root:$TRUENAS_PASSWORD" \
          "http://$TRUENAS_HOST/api/v2.0/core/get_jobs?id=$JOB_ID" \
          | jq -r '.[0].state')
        echo "    Attempt $i/30: state=$STATE"
        [ "$STATE" = "SUCCESS" ] && break
        [ "$STATE" = "FAILED"  ] && echo "ERROR: TrueNAS app update job $JOB_ID failed" && exit 1
        sleep 5
      done
      [ "$STATE" != "SUCCESS" ] && echo "ERROR: App update job timed out after 150s" && exit 1

      echo "==> App redeployed. Waiting for OpenClaw to become reachable..."
      sleep 30
      for i in $(seq 1 60); do
        HTTP=$(curl -o /dev/null -sw "%%{http_code}" "http://$TRUENAS_HOST:30262/" 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && echo "==> OpenClaw is up and healthy (HTTP 200)." && exit 0
        echo "    Attempt $i/60: HTTP $HTTP — retrying in 5s..."
        sleep 5
      done

      echo "ERROR: OpenClaw health check failed after 330s (last HTTP code: $HTTP)"
      exit 1
    EOT
  }
}

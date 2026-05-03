# OpenClaw AWS Bedrock Integration — Implementation Spec

## 1. Purpose

Provision all AWS resources and configure the running OpenClaw instance on TrueNAS so that OpenClaw can use AWS Bedrock as its AI provider. Everything is managed by Terraform in this repository. After `terraform apply`, OpenClaw should present Amazon Bedrock models in its UI with no further manual steps (except one one-time AWS console model-access step documented in §11).

---

## 2. Current State

| Component | State |
|---|---|
| OpenClaw app | Running at `http://10.0.0.160:30262/`, version `2026.4.27 / 1.0.25` |
| OpenClaw config | Gateway token set; no AI provider configured |
| AWS account `aws-openclaw-ai` | Exists (ID `914713788242`); no Bedrock IAM user yet |
| Terraform code | None — this repository is empty |

---

## 3. Target State

- IAM user `openclaw-bedrock` exists in account `914713788242` with `AmazonBedrockFullAccess`
- An active IAM access key is generated for that user
- The OpenClaw container has env vars `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION` set
- `openclaw.json` on TrueNAS contains the Bedrock provider and plugin config blocks (deep-merged, existing keys preserved)
- OpenClaw is restarted and Bedrock models are discoverable in the UI

---

## 4. Repository Layout

```
openclaw-truenas-infra/
├── docs/
│   └── SPEC.md              ← this file
├── terraform/
│   ├── providers.tf         ← provider declarations and version pins
│   ├── variables.tf         ← all input variables
│   ├── main.tf              ← IAM user, policy attachment, access key
│   ├── truenas.tf           ← null_resource blocks for TrueNAS config changes
│   └── outputs.tf           ← sensitive credential outputs
└── .gitignore               ← must exclude state files and tfvars
```

---

## 5. Prerequisites

The following must be satisfied on the operator's machine before `terraform apply`:

| Requirement | How to satisfy |
|---|---|
| Terraform ≥ 1.5 | `brew install terraform` |
| AWS CLI with profile `aws-openclaw-ai` | Already configured via SSO |
| `jq` | `brew install jq` |
| `curl` | Included on macOS |
| TrueNAS at `10.0.0.160` reachable | On local network |
| OpenClaw app in RUNNING state | Verify: `curl -o /dev/null -sw "%{http_code}" http://10.0.0.160:30262/` returns `200` |

---

## 6. AWS Resources (`main.tf`)

### 6.1 IAM User

```hcl
resource "aws_iam_user" "openclaw_bedrock" {
  name = "openclaw-bedrock"
  path = "/openclaw/"
  tags = {
    Project   = "openclaw"
    ManagedBy = "terraform"
  }
}
```

### 6.2 IAM Policy Attachment

```hcl
resource "aws_iam_user_policy_attachment" "bedrock_full_access" {
  user       = aws_iam_user.openclaw_bedrock.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}
```

### 6.3 IAM Access Key

```hcl
resource "aws_iam_access_key" "openclaw_bedrock" {
  user = aws_iam_user.openclaw_bedrock.name
}
```

The key ID and secret are referenced as `aws_iam_access_key.openclaw_bedrock.id` and `aws_iam_access_key.openclaw_bedrock.secret` in `truenas.tf`.

---

## 7. Providers (`providers.tf`)

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}
```

---

## 8. Variables (`variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_profile` | `string` | `"aws-openclaw-ai"` | AWS CLI named profile for SSO |
| `aws_region` | `string` | `"us-east-1"` | AWS region for IAM and Bedrock |
| `truenas_host` | `string` | `"10.0.0.160"` | TrueNAS server IP |
| `truenas_password` | `string` (sensitive) | — | TrueNAS `root` password. Supply via `-var` flag or `terraform.tfvars` (gitignored). Current value: `admin1` |

---

## 9. TrueNAS Configuration (`truenas.tf`)

All three resources depend on `aws_iam_access_key.openclaw_bedrock`. All use `local-exec` provisioners with `curl` and `jq` against `http://${var.truenas_host}/api/v2.0` authenticated as `root:${var.truenas_password}`.

### 9.1 Update `openclaw.json` — deep-merge Bedrock config

**What to do:** Read the current `openclaw.json`, deep-merge the Bedrock provider and plugin blocks into it (preserving all existing keys), and write it back.

**Config file path on TrueNAS:**
```
/mnt/.ix-apps/app_mounts/openclaw/config/.openclaw/openclaw.json
```

**Bedrock block to merge in:**
```json
{
  "models": {
    "providers": {
      "amazon-bedrock": {
        "baseUrl": "https://bedrock-runtime.us-east-1.amazonaws.com",
        "api": "bedrock-converse-stream",
        "auth": "aws-sdk"
      }
    }
  },
  "plugins": {
    "entries": {
      "amazon-bedrock": {
        "config": {
          "discovery": {
            "enabled": true,
            "region": "us-east-1"
          }
        }
      }
    }
  }
}
```

**Implementation — `local-exec` script:**

```bash
# 1. Read current config
curl -sf -u root:${TRUENAS_PASSWORD} \
  -X POST "http://${TRUENAS_HOST}/api/v2.0/filesystem/get" \
  -H "Content-Type: application/json" \
  -d '"/mnt/.ix-apps/app_mounts/openclaw/config/.openclaw/openclaw.json"' \
  > /tmp/openclaw_current.json

# 2. Deep-merge (. * $patch keeps existing keys, adds new ones)
jq --argjson patch '{
  "models": {"providers": {"amazon-bedrock": {
    "baseUrl": "https://bedrock-runtime.us-east-1.amazonaws.com",
    "api": "bedrock-converse-stream", "auth": "aws-sdk"
  }}},
  "plugins": {"entries": {"amazon-bedrock": {
    "config": {"discovery": {"enabled": true, "region": "us-east-1"}}
  }}}
}' '. * $patch' /tmp/openclaw_current.json > /tmp/openclaw_merged.json

# 3. Write back
curl -sf -u root:${TRUENAS_PASSWORD} \
  -X POST "http://${TRUENAS_HOST}/api/v2.0/filesystem/put" \
  -F 'data={"path":"/mnt/.ix-apps/app_mounts/openclaw/config/.openclaw/openclaw.json","mode":"0644"}' \
  -F "file=@/tmp/openclaw_merged.json"
```

### 9.2 Inject AWS credentials as container env vars

**What to do:** Update the OpenClaw TrueNAS app with the three AWS env vars so the AWS SDK inside the container can authenticate to Bedrock.

**API endpoint:** `PUT /api/v2.0/app/id/openclaw`  
**Body:** `{"values": { <env var schema — see below> }}`

This endpoint returns a numeric job ID. Poll `GET /api/v2.0/core/get_jobs?id={JOB_ID}` until `state` is `"SUCCESS"` or `"FAILED"`.

**⚠ Schema investigation required:** The exact key path inside `values` for environment variables is defined in the OpenClaw app's `questions.yaml`. Before implementing this `null_resource`, read that file:

```bash
ssh root@10.0.0.160 \
  "cat /mnt/.ix-apps/app_configs/openclaw/versions/1.0.25/questions.yaml"
```

Search for the field that controls extra/additional environment variables. Based on standard TrueNAS community app patterns, the three most likely schemas are:

| Pattern | Example `values` body |
|---|---|
| List of name/value pairs | `{"extraEnvs": [{"name": "AWS_ACCESS_KEY_ID", "value": "AKIA..."}]}` |
| Nested under app key | `{"openclaw": {"env": {"AWS_ACCESS_KEY_ID": "AKIA..."}}}` |
| Top-level map | `{"env": {"AWS_ACCESS_KEY_ID": "AKIA..."}}` |

Use whichever matches the `questions.yaml` field name. If the app exposes no env var field at all, see §10 (fallback).

**Implementation — `local-exec` script:**

```bash
JOB_ID=$(curl -sf -u root:${TRUENAS_PASSWORD} \
  -X PUT "http://${TRUENAS_HOST}/api/v2.0/app/id/openclaw" \
  -H "Content-Type: application/json" \
  -d "{\"values\": {<SCHEMA FROM QUESTIONS.YAML>}}")

# Poll until done (max 150s)
for i in $(seq 1 30); do
  STATE=$(curl -sf -u root:${TRUENAS_PASSWORD} \
    "http://${TRUENAS_HOST}/api/v2.0/core/get_jobs?id=${JOB_ID}" \
    | jq -r '.[0].state')
  [ "$STATE" = "SUCCESS" ] && break
  [ "$STATE" = "FAILED"  ] && echo "App update job failed" && exit 1
  sleep 5
done
[ "$STATE" != "SUCCESS" ] && echo "App update timed out" && exit 1
```

### 9.3 Restart OpenClaw

After resources 9.1 and 9.2 are complete, restart the app and confirm it comes back up.

```bash
curl -sf -u root:${TRUENAS_PASSWORD} \
  -X POST "http://${TRUENAS_HOST}/api/v2.0/app/id/openclaw/restart"

# Wait for app to be reachable
sleep 30
HTTP=$(curl -o /dev/null -sw "%{http_code}" http://${TRUENAS_HOST}:30262/)
[ "$HTTP" != "200" ] && echo "OpenClaw did not come back up (HTTP $HTTP)" && exit 1
echo "OpenClaw is up."
```

`depends_on` order: `9.3` depends on `9.1` and `9.2`; `9.2` depends on `9.1`.

---

## 10. Fallback: env vars not supported via app update API

If the OpenClaw `questions.yaml` does not expose an environment variable field, use this fallback instead of §9.2:

**Directly edit `user_config.yaml`** to inject env vars, then restart:

File path: `/mnt/.ix-apps/app_configs/openclaw/versions/1.0.25/user_config.yaml`

Read the file via SSH (`ssh root@10.0.0.160 "cat <path>"`), add the three `AWS_*` vars to whatever env section exists, write it back via `filesystem/put`, then restart the app via `POST /app/id/openclaw/restart`.

This is less clean than §9.2 but equally effective and does not require knowing the Helm values schema.

---

## 11. Outputs (`outputs.tf`)

```hcl
output "iam_user_arn" {
  value       = aws_iam_user.openclaw_bedrock.arn
  description = "ARN of the openclaw-bedrock IAM user"
}

output "bedrock_access_key_id" {
  value     = aws_iam_access_key.openclaw_bedrock.id
  sensitive = true
}

output "bedrock_secret_access_key" {
  value     = aws_iam_access_key.openclaw_bedrock.secret
  sensitive = true
}
```

Retrieve after apply:
```bash
terraform output -raw bedrock_access_key_id
terraform output -raw bedrock_secret_access_key
```

---

## 12. `.gitignore`

```
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
```

`terraform.lock.hcl` may be committed for reproducibility (optional).

---

## 13. Execution

```bash
# Authenticate AWS SSO (one-time per session)
aws sso login --profile aws-openclaw-ai

cd terraform
terraform init
terraform plan  -var="truenas_password=admin1"
terraform apply -var="truenas_password=admin1"
```

---

## 14. Bedrock Model Access

The AWS **Model access** page has been retired. Serverless foundation models are now automatically enabled on first invocation — no manual opt-in required.

**Anthropic models only:** First-time use may prompt you to submit use case details in-browser before the call succeeds. This happens on the first prompt, not before `terraform apply`.

---

## 15. Acceptance Criteria

- [ ] `aws iam get-user --user-name openclaw-bedrock --profile aws-openclaw-ai` returns the user object
- [ ] `aws iam list-attached-user-policies --user-name openclaw-bedrock --profile aws-openclaw-ai` includes `AmazonBedrockFullAccess`
- [ ] `terraform output -raw bedrock_access_key_id` returns a non-empty key ID
- [ ] `curl -sf -u root:admin1 -X POST http://10.0.0.160/api/v2.0/filesystem/get -H "Content-Type: application/json" -d '"/mnt/.ix-apps/app_mounts/openclaw/config/.openclaw/openclaw.json"' | jq '.models.providers."amazon-bedrock"'` returns the Bedrock provider object
- [ ] OpenClaw web UI at `http://10.0.0.160:30262/` lists Amazon Bedrock as an available provider
- [ ] A test prompt using a Bedrock model (e.g. `anthropic.claude-3-5-sonnet-20241022-v2:0`) completes successfully

---

## 16. Key Values Reference

| Item | Value |
|---|---|
| TrueNAS host | `10.0.0.160` |
| TrueNAS root password | `admin1` |
| OpenClaw web UI | `http://10.0.0.160:30262/` |
| OpenClaw config path | `/mnt/.ix-apps/app_mounts/openclaw/config/.openclaw/openclaw.json` |
| OpenClaw app version | `2026.4.27 / 1.0.25` |
OpenClaw gateway token | [OPENCLAW_GATEWAY_TOKEN]
| AWS account name | `aws-openclaw-ai` |
| AWS account ID | `914713788242` |
| AWS region | `us-east-1` |
| AWS SSO portal | `https://ssoins-7223a39a1a337b87.portal.us-east-1.app.aws/#/` |
| IAM user to create | `openclaw-bedrock` |
| Bedrock API endpoint | `https://bedrock-runtime.us-east-1.amazonaws.com` |
untime.us-east-1.amazonaws.com` |

# OpenClaw TrueNAS Infrastructure

Infrastructure as Code (IaC) for managing [OpenClaw](https://openclaw.ai/) on TrueNAS with Amazon Bedrock integration.

## Overview

This repository uses Terraform to:
1.  **Provision AWS Resources:** Creates an IAM user with `AmazonBedrockFullAccess` and generates access keys.
2.  **Configure TrueNAS:** Updates the OpenClaw configuration file (`openclaw.json`) and injects AWS credentials into the app container via the TrueNAS API.
3.  **Automate Deployment:** Restarts the OpenClaw app to ensure all changes are applied and models are discovered.
4.  **Manage State:** Stores Terraform state in a versioned S3 bucket for durability and collaboration.

## Prerequisites

-   **AWS CLI:** Configured with an SSO profile named `aws-openclaw-ai`.
-   **Terraform:** Version 1.5 or higher.
-   **S3 Bucket:** `openclaw-truenas-infra-tfstate-914713788242` (Already created and managed by this project).
-   **SSH Access:** Required for reliable configuration updates on TrueNAS.
-   **Utilities:** `jq`, `curl`, and `sshpass` installed on the operator's machine.

## Deployment

1.  **Authenticate AWS:**
    ```bash
    aws sso login --profile aws-openclaw-ai
    ```

2.  **Set Secrets:**
    It is recommended to use environment variables to avoid sensitive data in command history:
    ```bash
    export TF_VAR_truenas_password="YOUR_PASSWORD"
    export TF_VAR_github_token="YOUR_GITHUB_PAT" # Optional: syncs keys to GitHub Secrets
    ```

3.  **Run Terraform:**
    ```bash
    cd terraform
    terraform init
    terraform apply
    ```

## Secret Management

This project automatically syncs sensitive outputs to your GitHub repository secrets if `github_token` is provided. This allows other tools or CI/CD pipelines to access the provisioned credentials without manual entry.

The following secrets are managed:
- `BEDROCK_ACCESS_KEY_ID`: Synced from AWS IAM output.
- `BEDROCK_SECRET_ACCESS_KEY`: Synced from AWS IAM output.

## Accessing OpenClaw

Once deployed, OpenClaw is accessible via your local network:

-   **Web UI:** [http://10.0.0.160:30262/](http://10.0.0.160:30262/)
-   **Default Admin Token:** `fcf8e201f225a90912a002a139b871cfbfa2a6de5aef671c` (Set via Gateway Token)

## Using Amazon Bedrock

1.  Open the OpenClaw Web UI.
2.  Navigate to **Settings > Providers**.
3.  Ensure **Amazon Bedrock** is enabled.
4.  In the **Chat** interface, you can now select Bedrock models (e.g., `anthropic.claude-3-5-sonnet-20241022-v2:0`).

> **Note:** Models are automatically discovered. If a specific model is not listed, verify that you have enabled access for it in the AWS Console (Bedrock > Model access).

## Troubleshooting

-   **Logs:** Check the container logs via SSH:
    ```bash
    ssh root@10.0.0.160 "docker logs \$(docker ps -q --filter name=openclaw)"
    ```
-   **Config Path:** The main configuration is stored at:
    `/mnt/.ix-apps/app_mounts/openclaw/config/.openclaw/openclaw.json`
-   **API Issues:** If the TrueNAS API fails to update environment variables, Terraform will report a job failure. Check the job status in the TrueNAS UI or via `curl`.

## License

This project is licensed under the MIT License.

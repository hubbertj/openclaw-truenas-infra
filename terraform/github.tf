# Manage sensitive outputs as GitHub Actions Secrets.
# This ensures that once Terraform runs locally, the generated credentials
# are safely backed up in the GitHub repository secrets.

data "github_actions_public_key" "repo" {
  count      = var.github_token != null ? 1 : 0
  repository = split("/", var.github_repository)[1]
}

resource "github_actions_secret" "bedrock_access_key_id" {
  count           = var.github_token != null ? 1 : 0
  repository      = split("/", var.github_repository)[1]
  secret_name     = "BEDROCK_ACCESS_KEY_ID"
  plaintext_value = aws_iam_access_key.openclaw_bedrock.id
}

resource "github_actions_secret" "bedrock_secret_access_key" {
  count           = var.github_token != null ? 1 : 0
  repository      = split("/", var.github_repository)[1]
  secret_name     = "BEDROCK_SECRET_ACCESS_KEY"
  plaintext_value = aws_iam_access_key.openclaw_bedrock.secret
}

locals {
  effective_truenas_password = var.truenas_password
}

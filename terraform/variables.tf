variable "aws_profile" {
  type        = string
  default     = "aws-openclaw-ai"
  description = "AWS CLI named profile (SSO)"
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for IAM and Bedrock"
}

variable "truenas_host" {
  type        = string
  default     = "10.0.0.160"
  description = "TrueNAS server IP"
}

variable "truenas_password" {
  type        = string
  sensitive   = true
  description = "TrueNAS root password. Recommended: set via 'TF_VAR_truenas_password' env var."
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token for managing secrets."
  default     = null
}

variable "github_repository" {
  type        = string
  default     = "hubbertj/openclaw-truenas-infra"
  description = "GitHub repository name (owner/repo)."
}

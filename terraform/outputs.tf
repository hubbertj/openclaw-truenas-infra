output "iam_user_arn" {
  value       = aws_iam_user.openclaw_bedrock.arn
  description = "ARN of the openclaw-bedrock IAM user"
}

output "bedrock_access_key_id" {
  value       = aws_iam_access_key.openclaw_bedrock.id
  sensitive   = true
  description = "AWS access key ID for Bedrock"
}

output "bedrock_secret_access_key" {
  value       = aws_iam_access_key.openclaw_bedrock.secret
  sensitive   = true
  description = "AWS secret access key for Bedrock"
}

output "openclaw_vm_ip" {
  value       = var.openclaw_vm_host
  description = "The IP address of the OpenClaw VM."
}

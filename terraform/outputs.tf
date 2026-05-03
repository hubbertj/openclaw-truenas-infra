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

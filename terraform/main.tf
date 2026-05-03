resource "aws_iam_user" "openclaw_bedrock" {
  name = "openclaw-bedrock"
  path = "/openclaw/"

  tags = {
    Project   = "openclaw"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_user_policy_attachment" "bedrock_full_access" {
  user       = aws_iam_user.openclaw_bedrock.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

resource "aws_iam_access_key" "openclaw_bedrock" {
  user = aws_iam_user.openclaw_bedrock.name
}

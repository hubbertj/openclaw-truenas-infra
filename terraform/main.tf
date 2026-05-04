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

locals {
  bedrock_config = {
    models = {
      providers = {
        "amazon-bedrock" = {
          baseUrl = "https://bedrock-runtime.us-east-1.amazonaws.com"
          api     = "bedrock-converse-stream"
          auth    = "aws-sdk"
          models  = [
            "us.anthropic.claude-opus-4-7",
            "us.anthropic.claude-sonnet-4-6",
            "us.anthropic.claude-opus-4-5-20251101-v1:0",
            "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
          ]
        }
        "bedrock" = {
          baseUrl = "https://bedrock-runtime.us-east-1.amazonaws.com"
          api     = "bedrock-converse-stream"
          auth    = "aws-sdk"
          models  = [
            "us.anthropic.claude-opus-4-7",
            "us.anthropic.claude-sonnet-4-6",
            "us.anthropic.claude-opus-4-5-20251101-v1:0",
            "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
          ]
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

terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket  = "openclaw-truenas-infra-tfstate-914713788242"
    key     = "terraform.tfstate"
    region  = "us-east-1"
    profile = "aws-openclaw-ai"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

provider "github" {
  token = var.github_token
  owner = split("/", var.github_repository)[0]
}

terraform {
  required_version = "~> 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71.0"
    }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = {
      Project     = var.prefix
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

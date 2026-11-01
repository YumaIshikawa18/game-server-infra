terraform {
  required_version = "~> 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8.0"
    }
  }

  # bucket / key / region は partial configuration で渡す（CI は Secrets、手元は gitignore 済みの backend.hcl）。
  backend "s3" {
    encrypt      = true
    use_lockfile = true
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

# bootstrap は CI/CD の前提を作るため、ローカルから一度だけ apply する。
# state はローカル（terraform.tfstate、.gitignore 済み）に置く。紛失すると以後の変更ができなくなるため安全な場所に保管すること。
terraform {
  required_version = "~> 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      Component = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}

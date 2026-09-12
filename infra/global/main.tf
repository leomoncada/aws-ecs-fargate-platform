# Global/shared resources: one ECR repo per app, used by all environments (staging, prod).
# Apply this root once per account/region before applying environment-specific infra.
# Environments differ only by image tag (staging vs prod), not by repository.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Use a separate state from per-env infra (e.g. key = "portfolio/global/terraform.tfstate")
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  # Cost allocation and ownership: applied to every resource in this root
  # so nothing has to remember to tag itself.
  default_tags {
    tags = {
      Project     = "portfolio"
      Environment = "global"
      ManagedBy   = "terraform"
      Owner       = "leomoncada"
    }
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "portfolio-backend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name = "portfolio-backend"
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "portfolio-frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name = "portfolio-frontend"
  }
}

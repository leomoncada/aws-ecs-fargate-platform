terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Configured at init time:
  #   terraform init -backend-config=backend.hcl
  # See backend-config.example.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  # Cost allocation and ownership: applied to every resource in this root
  # so nothing has to remember to tag itself.
  default_tags {
    tags = {
      Project     = "portfolio"
      Environment = "staging"
      ManagedBy   = "terraform"
      Owner       = "leomoncada"
    }
  }
}

module "portfolio" {
  source = "../../modules/portfolio"

  environment     = var.environment
  vpc_cidr        = var.vpc_cidr
  az_count        = var.az_count
  certificate_arn = var.certificate_arn
  backend_image   = var.backend_image
  frontend_image  = var.frontend_image
  ecs_cpu         = var.ecs_cpu
  ecs_memory_mb   = var.ecs_memory_mb
  alarm_email     = var.alarm_email
  allowed_origins = var.allowed_origins
}

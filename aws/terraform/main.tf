################################################################################
# NHCE Lost & Found — Terraform Main Configuration
# Provider setup, backend, and shared data sources
################################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # S3 backend for remote state — comment out for first-time setup
  # Uncomment after creating the bucket manually (bootstrap step)
  # backend "s3" {
  #   bucket         = "nhce-lostandfound-tfstate"
  #   key            = "prod/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "nhce-tf-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "NHCE-LostAndFound"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Chandugv"
    }
  }
}

# Fetch current AWS account info
data "aws_caller_identity" "current" {}

# Fetch available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

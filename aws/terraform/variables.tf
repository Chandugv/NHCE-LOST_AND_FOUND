################################################################################
# NHCE Lost & Found — Terraform Variables
################################################################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"  # Mumbai — closest to Bangalore/NHCE
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Short project name used for resource naming"
  type        = string
  default     = "nhce-laf"
}

# ─── Network ──────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EC2 + RDS)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ─── EC2 / Compute ────────────────────────────────────────────────────────────

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"  # Free Tier eligible
}

variable "key_pair_name" {
  description = "Name of existing EC2 Key Pair for SSH access (create in AWS Console first)"
  type        = string
  default     = "nhce-laf-keypair"
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 1
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 4
}

# ─── RDS Database ─────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"  # Free Tier eligible
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "nhce_lostandfound"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "nhce_admin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for RDS (use a strong password)"
  type        = string
  sensitive   = true
  # Set via: export TF_VAR_db_password="your-secure-password"
}

variable "db_allocated_storage" {
  description = "Storage in GB for RDS instance"
  type        = number
  default     = 20  # Free Tier max
}

# ─── Application ──────────────────────────────────────────────────────────────

variable "flask_secret_key" {
  description = "Flask SECRET_KEY for session signing"
  type        = string
  sensitive   = true
  # Set via: export TF_VAR_flask_secret_key="your-secret-key"
}

variable "mail_username" {
  description = "Gmail username for Flask-Mailman SMTP"
  type        = string
  default     = ""
}

variable "mail_password" {
  description = "Gmail App Password for Flask-Mailman SMTP"
  type        = string
  sensitive   = true
  default     = ""
}

variable "app_port" {
  description = "Port that Gunicorn listens on"
  type        = number
  default     = 8000
}

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

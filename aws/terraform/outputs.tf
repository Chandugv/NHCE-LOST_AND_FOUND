################################################################################
# NHCE Lost & Found — Terraform Outputs
# Values exported after terraform apply — use these to configure the app
################################################################################

# ─── Network ──────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets (ALB)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets (EC2 + RDS)"
  value       = aws_subnet.private[*].id
}

# ─── Application Access ────────────────────────────────────────────────────────

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer — access your app here"
  value       = "http://${aws_lb.main.dns_name}:8080"
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

# ─── Database ─────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS PostgreSQL connection endpoint"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "rds_database_name" {
  description = "Name of the PostgreSQL database"
  value       = aws_db_instance.postgres.db_name
}

output "database_url" {
  description = "Full DATABASE_URL for Flask app (password stored in SSM)"
  value       = "postgresql://${var.db_username}:<PASSWORD_FROM_SSM>@${aws_db_instance.postgres.address}:5432/${var.db_name}"
  sensitive   = true
}

# ─── Storage ──────────────────────────────────────────────────────────────────

output "images_bucket_name" {
  description = "Name of the S3 bucket for image uploads"
  value       = aws_s3_bucket.images.bucket
}

output "static_bucket_url" {
  description = "URL for the static assets S3 bucket"
  value       = aws_s3_bucket_website_configuration.static.website_endpoint
}

# ─── Container Registry ───────────────────────────────────────────────────────

output "ecr_repository_url" {
  description = "ECR repository URL — push Docker images here"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_docker_push_commands" {
  description = "Commands to build and push Docker image to ECR"
  value       = <<-EOT
    # Authenticate Docker to ECR
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}
    
    # Build the image
    docker build -t ${var.project_name}-app -f aws/docker/Dockerfile .
    
    # Tag and push
    docker tag ${var.project_name}-app:latest ${aws_ecr_repository.app.repository_url}:latest
    docker push ${aws_ecr_repository.app.repository_url}:latest
  EOT
}

# ─── IAM ──────────────────────────────────────────────────────────────────────

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

# ─── Monitoring ───────────────────────────────────────────────────────────────

output "cloudwatch_dashboard_url" {
  description = "Direct URL to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "app_log_group" {
  description = "CloudWatch Log Group for application logs"
  value       = aws_cloudwatch_log_group.app_logs.name
}

# ─── Summary ──────────────────────────────────────────────────────────────────

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value       = <<-EOT
    ╔══════════════════════════════════════════════════════════╗
    ║       NHCE Lost & Found — AWS Deployment Complete        ║
    ╠══════════════════════════════════════════════════════════╣
    ║ App URL:      http://${aws_lb.main.dns_name}:8080
    ║ Region:       ${var.aws_region}
    ║ Environment:  ${var.environment}
    ║ ECR Repo:     ${aws_ecr_repository.app.repository_url}
    ║ DB Endpoint:  ${aws_db_instance.postgres.address}
    ║ Images S3:    ${aws_s3_bucket.images.bucket}
    ╚══════════════════════════════════════════════════════════╝
  EOT
}

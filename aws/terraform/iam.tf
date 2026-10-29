################################################################################
# NHCE Lost & Found — IAM Roles, Policies, and Instance Profiles
# Principle of Least Privilege: services only get permissions they need
################################################################################

# ─── EC2 Instance Role ────────────────────────────────────────────────────────
# This role is assumed by EC2 instances to interact with AWS services

resource "aws_iam_role" "ec2_instance_role" {
  name        = "${var.project_name}-ec2-role"
  description = "Role assumed by EC2 instances running the Flask app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# ─── EC2 Policies ─────────────────────────────────────────────────────────────

# 1. S3 access: read static assets, write/read uploaded images
resource "aws_iam_policy" "ec2_s3_policy" {
  name        = "${var.project_name}-ec2-s3-policy"
  description = "Allow EC2 to read/write Lost&Found S3 buckets only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowImageBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.images.arn,
          "${aws_s3_bucket.images.arn}/*"
        ]
      },
      {
        Sid    = "AllowStaticBucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.static.arn,
          "${aws_s3_bucket.static.arn}/*"
        ]
      }
    ]
  })
}

# 2. CloudWatch Logs: push application logs
resource "aws_iam_policy" "ec2_cloudwatch_policy" {
  name        = "${var.project_name}-ec2-cloudwatch-policy"
  description = "Allow EC2 to write logs and custom metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/nhce-lostandfound/*"
      },
      {
        Sid    = "AllowCloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowEC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# 3. SSM Parameter Store: read secrets (DB password, Flask secret key)
resource "aws_iam_policy" "ec2_ssm_policy" {
  name        = "${var.project_name}-ec2-ssm-policy"
  description = "Allow EC2 to read secrets from SSM Parameter Store"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowSSMParameterRead"
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/nhce-lostandfound/*"
    },
    {
      Sid    = "AllowKMSDecrypt"
      Effect = "Allow"
      Action = ["kms:Decrypt"]
      Resource = "*"
    }]
  })
}

# 4. ECR: pull Docker images
resource "aws_iam_policy" "ec2_ecr_policy" {
  name        = "${var.project_name}-ec2-ecr-policy"
  description = "Allow EC2 to pull images from ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowECRPull"
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ]
      Resource = "*"
    }]
  })
}

# Attach all policies to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.ec2_cloudwatch_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.ec2_ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_ecr" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.ec2_ecr_policy.arn
}

# Allow SSM Session Manager (secure SSH alternative — no port 22 needed)
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ─── EC2 Instance Profile ─────────────────────────────────────────────────────
# This is attached to EC2 launch template

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_role.name
}

# ─── ECR Repository ───────────────────────────────────────────────────────────
# Docker image registry for the Flask app

resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true  # Automatically scan for vulnerabilities
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Auto-clean old images: keep only last 10
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ─── SSM Parameters (Secrets Storage) ────────────────────────────────────────
# Secrets are stored in SSM and fetched at runtime — never in env files

resource "aws_ssm_parameter" "db_password" {
  name        = "/nhce-lostandfound/db_password"
  description = "RDS master password"
  type        = "SecureString"
  value       = var.db_password
}

resource "aws_ssm_parameter" "flask_secret_key" {
  name        = "/nhce-lostandfound/flask_secret_key"
  description = "Flask SECRET_KEY"
  type        = "SecureString"
  value       = var.flask_secret_key
}

resource "aws_ssm_parameter" "mail_password" {
  name        = "/nhce-lostandfound/mail_password"
  description = "Gmail App Password for SMTP"
  type        = "SecureString"
  value       = var.mail_password != "" ? var.mail_password : "placeholder"
}

################################################################################
# NHCE Lost & Found — Security Groups
# Principle of least privilege: each SG only allows what's needed
################################################################################

# ─── ALB Security Group ────────────────────────────────────────────────────────
# Accepts HTTP (80) and HTTPS (443) from anywhere on the internet

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP/HTTPS inbound from internet to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound (to reach EC2 instances)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# ─── EC2 Security Group ────────────────────────────────────────────────────────
# Only accepts traffic from the ALB on the app port (8000)
# No direct internet access — all traffic goes through ALB

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow app traffic only from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Uncomment for emergency SSH via Systems Manager (Session Manager preferred)
  # ingress {
  #   description = "SSH from admin IP only — CHANGE THIS"
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["YOUR.ADMIN.IP.HERE/32"]
  # }

  egress {
    description = "Allow all outbound (for pulling images, updates)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ec2-sg" }
}

# ─── RDS Security Group ────────────────────────────────────────────────────────
# Only accepts PostgreSQL (5432) from EC2 instances
# Database is never exposed to the internet

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow PostgreSQL traffic only from EC2 instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EC2 only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-rds-sg" }
}

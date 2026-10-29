################################################################################
# NHCE Lost & Found — RDS PostgreSQL Database
# Managed relational database replacing SQLite for production
################################################################################

# DB Subnet Group: RDS must span multiple AZs (even if not Multi-AZ)
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Subnet group for NHCE Lost&Found RDS — private subnets only"
  subnet_ids  = aws_subnet.private[*].id

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

# DB Parameter Group: PostgreSQL tuning for a small web app
resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project_name}-pg15-params"
  family      = "postgres15"
  description = "Custom parameters for NHCE Lost&Found PostgreSQL 15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "0"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"   # Log queries taking > 1 second
  }
}

# ─── RDS PostgreSQL Instance ──────────────────────────────────────────────────

resource "aws_db_instance" "postgres" {
  identifier     = "${var.project_name}-postgres"
  engine         = "postgres"
  engine_version = "15.4"

  # Instance sizing — db.t3.micro is Free Tier eligible
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100  # Enable storage auto-scaling up to 100 GB
  storage_type          = "gp2"
  storage_encrypted     = true

  # Database credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false  # NEVER expose DB to internet

  # Parameter & option groups
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Backup & maintenance
  backup_retention_period = 7         # Keep 7 days of automated backups
  backup_window           = "03:00-04:00"   # UTC — 8:30–9:30 AM IST
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Deletion protection (set to true for production)
  deletion_protection      = false
  skip_final_snapshot      = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot"

  # Enhanced monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Performance Insights (free for 7 days retention)
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = { Name = "${var.project_name}-postgres" }
}

# ─── RDS Enhanced Monitoring Role ────────────────────────────────────────────

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ─── RDS Connection String Output (used in EC2 user_data) ────────────────────

# The full connection string is assembled from outputs
# Format: postgresql://username:password@endpoint:5432/dbname

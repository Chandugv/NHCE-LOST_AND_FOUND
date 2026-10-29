################################################################################
# NHCE Lost & Found — CloudWatch Monitoring
# Dashboards, alarms, log groups for full observability
################################################################################

# ─── Log Groups ───────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/nhce-lostandfound/app"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "error_logs" {
  name              = "/nhce-lostandfound/errors"
  retention_in_days = 90   # Keep errors longer for debugging
}

resource "aws_cloudwatch_log_group" "alb_logs" {
  name              = "/nhce-lostandfound/alb"
  retention_in_days = 7
}

# ─── CloudWatch Alarms ────────────────────────────────────────────────────────

# 1. ALB 5xx errors — something is broken in the app
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALERT: 10+ server errors in 1 minute — investigate app logs"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# 2. RDS High DB Connections — potential connection leak
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project_name}-rds-high-connections"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ALERT: RDS connection count is high (>80)"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.id
  }
}

# 3. RDS Low Free Storage
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project_name}-rds-low-storage"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2000000000   # 2 GB in bytes
  alarm_description   = "WARNING: RDS free storage is below 2 GB"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.id
  }
}

# 4. ALB Unhealthy Hosts — instances failing health checks
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "ALERT: One or more instances are unhealthy in the target group"

  dimensions = {
    TargetGroup  = aws_lb_target_group.app.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# 5. ALB Response Time — app is slow
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${var.project_name}-high-latency"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "p95"
  threshold           = 3   # 3 seconds p95 latency
  alarm_description   = "WARNING: p95 response time > 3 seconds"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# 6. EC2 CPU High Alarm (monitoring, separate from ASG scaling)
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_critical" {
  alarm_name          = "${var.project_name}-cpu-critical"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "CRITICAL: EC2 CPU > 90% — application may be overloaded"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

# ─── CloudWatch Dashboard ─────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ── Title ──
      {
        type   = "text"
        x      = 0; y = 0; width = 24; height = 2
        properties = {
          markdown = "# 🎒 NHCE Lost & Found — Live Dashboard\n**Region:** ${var.aws_region} | **Environment:** ${var.environment}"
        }
      },
      # ── ALB Request Count ──
      {
        type = "metric"; x = 0; y = 2; width = 8; height = 6
        properties = {
          title  = "📈 Requests / Minute"
          view   = "timeSeries"
          period = 60
          metrics = [[
            "AWS/ApplicationELB",
            "RequestCount",
            "LoadBalancer",
            aws_lb.main.arn_suffix,
            { stat = "Sum", label = "Total Requests" }
          ]]
        }
      },
      # ── ALB Error Rate ──
      {
        type = "metric"; x = 8; y = 2; width = 8; height = 6
        properties = {
          title  = "❌ HTTP Errors"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum", label = "4xx Client Errors" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum", label = "5xx Server Errors" }]
          ]
        }
      },
      # ── Response Time ──
      {
        type = "metric"; x = 16; y = 2; width = 8; height = 6
        properties = {
          title  = "⏱️ Response Time (p95)"
          view   = "timeSeries"
          period = 60
          metrics = [[
            "AWS/ApplicationELB",
            "TargetResponseTime",
            "LoadBalancer",
            aws_lb.main.arn_suffix,
            { stat = "p95", label = "p95 Latency" }
          ]]
        }
      },
      # ── EC2 CPU ──
      {
        type = "metric"; x = 0; y = 8; width = 8; height = 6
        properties = {
          title  = "🖥️ EC2 CPU Utilization"
          view   = "timeSeries"
          period = 60
          metrics = [[
            "AWS/EC2",
            "CPUUtilization",
            "AutoScalingGroupName",
            aws_autoscaling_group.app.name,
            { stat = "Average", label = "Avg CPU %" }
          ]]
        }
      },
      # ── ASG Instance Count ──
      {
        type = "metric"; x = 8; y = 8; width = 8; height = 6
        properties = {
          title  = "⚖️ Auto Scaling — Instance Count"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/AutoScaling", "GroupInServiceCapacity", "AutoScalingGroupName", aws_autoscaling_group.app.name, { stat = "Average", label = "In-Service" }],
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", aws_autoscaling_group.app.name, { stat = "Average", label = "Desired" }]
          ]
        }
      },
      # ── RDS Metrics ──
      {
        type = "metric"; x = 16; y = 8; width = 8; height = 6
        properties = {
          title  = "🗄️ RDS Database"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.postgres.id, { stat = "Average", label = "Connections" }],
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.id, { stat = "Average", label = "CPU %" }]
          ]
        }
      },
      # ── Healthy Host Count ──
      {
        type = "metric"; x = 0; y = 14; width = 12; height = 6
        properties = {
          title  = "💚 Healthy vs Unhealthy Instances"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Average", label = "Healthy" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Average", label = "Unhealthy" }]
          ]
        }
      },
      # ── S3 Bucket Size ──
      {
        type = "metric"; x = 12; y = 14; width = 12; height = 6
        properties = {
          title  = "📦 S3 Storage Usage"
          view   = "timeSeries"
          period = 86400
          metrics = [[
            "AWS/S3",
            "BucketSizeBytes",
            "BucketName",
            aws_s3_bucket.images.bucket,
            "StorageType",
            "StandardStorage",
            { stat = "Average", label = "Image Bucket Size" }
          ]]
        }
      }
    ]
  })
}

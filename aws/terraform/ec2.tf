################################################################################
# NHCE Lost & Found — EC2 Launch Template + Auto Scaling Group
# High Availability: 2 instances across 2 AZs, scales 1–4
################################################################################

# ─── Launch Template ──────────────────────────────────────────────────────────

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  description   = "Launch template for NHCE Lost&Found Flask app"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.ec2_instance_type
  key_name      = var.key_pair_name

  # Attach IAM profile (S3, CloudWatch, SSM, ECR access)
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  # Network: private subnet, no direct public IP
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
    delete_on_termination       = true
  }

  # Root volume: encrypted, 20 GB gp3
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # User data: bootstrap script (base64-encoded)
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    aws_region       = var.aws_region
    ecr_repo_url     = aws_ecr_repository.app.repository_url
    image_tag        = var.docker_image_tag
    app_port         = var.app_port
    db_host          = aws_db_instance.postgres.address
    db_name          = var.db_name
    db_user          = var.db_username
    s3_images_bucket = aws_s3_bucket.images.bucket
    mail_username    = var.mail_username
  }))

  # Enable detailed monitoring (1-minute intervals)
  monitoring { enabled = true }

  # Metadata options: IMDSv2 required (security best practice)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-app-server"
      Application = "NHCE-LostAndFound"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = { Name = "${var.project_name}-root-volume" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Auto Scaling Group ────────────────────────────────────────────────────────

resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  min_size            = var.asg_min_size
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_size
  vpc_zone_identifier = aws_subnet.private[*].id   # Spread across private subnets

  # Link to Launch Template
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Register instances with ALB Target Group
  target_group_arns = [aws_lb_target_group.app.arn]

  # Health check: use ALB health checks (more reliable than EC2 status)
  health_check_type         = "ELB"
  health_check_grace_period = 180   # 3 minutes for app to start

  # Rolling deployment: replace instances one at a time
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
    }
  }

  # Ensure replacement before destroying (zero-downtime updates)
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]   # Allow manual scaling
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# ─── Auto Scaling Policies ────────────────────────────────────────────────────

# Scale OUT when CPU > 70% for 2 consecutive 5-minute periods
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300   # Wait 5 min before scaling again
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when average CPU > 70% for 10 minutes"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
  ok_actions    = [aws_autoscaling_policy.scale_in.arn]
}

# Scale IN when CPU < 30% for 10 consecutive 5-minute periods
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 10
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in when average CPU < 30% for 50 minutes"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
}

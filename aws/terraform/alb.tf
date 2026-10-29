################################################################################
# NHCE Lost & Found — Application Load Balancer
# Distributes traffic across EC2 instances, enables HTTPS
################################################################################

# ─── Load Balancer ────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false          # Internet-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id   # Spans 2 AZs

  enable_deletion_protection = false
  enable_http2               = true

  access_logs {
    bucket  = aws_s3_bucket.static.id
    prefix  = "alb-logs"
    enabled = true
  }

  tags = { Name = "${var.project_name}-alb" }
}

# ─── Target Group (EC2 instances) ─────────────────────────────────────────────

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"          # Flask app root returns 200
    protocol            = "HTTP"
    matcher             = "200-302"    # Allow redirects (e.g., login)
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400   # 24 hours — keeps user sessions on same instance
    enabled         = true
  }

  tags = { Name = "${var.project_name}-target-group" }
}

# ─── HTTP Listener (redirects to HTTPS) ──────────────────────────────────────

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ─── HTTPS Listener ───────────────────────────────────────────────────────────
# NOTE: Requires an ACM certificate. For initial testing, use HTTP only.
# Uncomment and add your domain's ACM certificate ARN when ready.

# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = "arn:aws:acm:ap-south-1:ACCOUNT_ID:certificate/CERT_ID"
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app.arn
#   }
# }

# ─── HTTP-only Listener for Testing (comment out if using HTTPS) ──────────────

resource "aws_lb_listener" "http_direct" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

#!/bin/bash
################################################################################
# NHCE Lost & Found — EC2 User Data Bootstrap Script
# Runs once when an EC2 instance first launches
# Installs Docker, pulls app image from ECR, starts Gunicorn container
################################################################################

set -euo pipefail

# ─── Variables (injected by Terraform templatefile) ──────────────────────────
AWS_REGION="${aws_region}"
ECR_REPO="${ecr_repo_url}"
IMAGE_TAG="${image_tag}"
APP_PORT="${app_port}"
DB_HOST="${db_host}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
S3_IMAGES_BUCKET="${s3_images_bucket}"
MAIL_USERNAME="${mail_username}"
LOG_GROUP="/nhce-lostandfound/app"

# ─── System Updates ───────────────────────────────────────────────────────────
echo "=== [1/8] Updating system packages ==="
dnf update -y
dnf install -y \
  docker \
  aws-cli \
  amazon-cloudwatch-agent \
  jq \
  htop \
  git

# ─── Docker Setup ─────────────────────────────────────────────────────────────
echo "=== [2/8] Starting Docker ==="
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# ─── CloudWatch Agent Setup ───────────────────────────────────────────────────
echo "=== [3/8] Configuring CloudWatch Agent ==="
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW_CONFIG'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nhce-app/app.log",
            "log_group_name": "/nhce-lostandfound/app",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/nhce-app/error.log",
            "log_group_name": "/nhce-lostandfound/errors",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "NHCE/LostAndFound",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_active", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60,
        "totalcpu": true
      },
      "mem": {
        "measurement": ["mem_used_percent", "mem_available_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      }
    },
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}",
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
    }
  }
}
CW_CONFIG

systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# ─── Create App Log Directory ─────────────────────────────────────────────────
echo "=== [4/8] Creating log directories ==="
mkdir -p /var/log/nhce-app
chown ec2-user:ec2-user /var/log/nhce-app

# ─── Fetch Secrets from SSM Parameter Store ───────────────────────────────────
echo "=== [5/8] Fetching secrets from SSM ==="
DB_PASSWORD=$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "/nhce-lostandfound/db_password" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text)

FLASK_SECRET_KEY=$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "/nhce-lostandfound/flask_secret_key" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text)

MAIL_PASSWORD=$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "/nhce-lostandfound/mail_password" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text)

# ─── Authenticate to ECR and Pull Docker Image ────────────────────────────────
echo "=== [6/8] Pulling Docker image from ECR ==="
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REPO"

docker pull "$ECR_REPO:$IMAGE_TAG"

# ─── Launch Flask App Container ───────────────────────────────────────────────
echo "=== [7/8] Starting NHCE Lost & Found container ==="

# Stop any existing container
docker stop nhce-app 2>/dev/null || true
docker rm nhce-app 2>/dev/null || true

docker run -d \
  --name nhce-app \
  --restart unless-stopped \
  -p "$APP_PORT:8000" \
  -e DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME" \
  -e SECRET_KEY="$FLASK_SECRET_KEY" \
  -e MAIL_USERNAME="$MAIL_USERNAME" \
  -e MAIL_PASSWORD="$MAIL_PASSWORD" \
  -e AWS_REGION="$AWS_REGION" \
  -e S3_IMAGES_BUCKET="$S3_IMAGES_BUCKET" \
  -e FLASK_ENV="production" \
  -v /var/log/nhce-app:/app/logs \
  "$ECR_REPO:$IMAGE_TAG"

# ─── Health Check ─────────────────────────────────────────────────────────────
echo "=== [8/8] Verifying app is running ==="
sleep 15

MAX_RETRIES=5
for i in $(seq 1 $MAX_RETRIES); do
  if curl -sf "http://localhost:$APP_PORT/" > /dev/null; then
    echo "✅ App is healthy and running on port $APP_PORT"
    
    # Send custom metric to CloudWatch
    aws cloudwatch put-metric-data \
      --region "$AWS_REGION" \
      --namespace "NHCE/LostAndFound" \
      --metric-name "InstanceStartup" \
      --value 1 \
      --unit Count
    break
  fi
  echo "Attempt $i/$MAX_RETRIES — waiting for app..."
  sleep 10
done

echo "=== Bootstrap complete! NHCE Lost & Found is running ==="

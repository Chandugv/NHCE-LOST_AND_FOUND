# 🎒 NHCE Lost & Found — AWS Cloud Engineering Deployment Guide

**Project:** NHCE-LOST_AND_FOUND | **Tech Stack:** Flask + PostgreSQL + Docker + Terraform + AWS

---

## 📋 Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [AWS Account Setup](#3-aws-account-setup)
4. [Infrastructure Deployment (Terraform)](#4-infrastructure-deployment-terraform)
5. [Docker Build & Push to ECR](#5-docker-build--push-to-ecr)
6. [CI/CD Pipeline Setup](#6-cicd-pipeline-setup)
7. [CloudWatch Monitoring](#7-cloudwatch-monitoring)
8. [Security Overview](#8-security-overview)
9. [Troubleshooting Guide](#9-troubleshooting-guide)
10. [Cost Estimate](#10-cost-estimate)
11. [Learning Topics Covered](#11-learning-topics-covered)

---

## 1. Architecture Overview

```
                          ┌─────────────────────────────────────────────────────┐
                          │                    AWS Cloud (ap-south-1)            │
                          │                                                       │
 Users ──── HTTPS ───────►│  ┌─────────────────────────────────────────────────┐│
 (Browser)                │  │   PUBLIC SUBNETS (10.0.1.0/24, 10.0.2.0/24)    ││
                          │  │                                                   ││
                          │  │  ┌──────────────────────────────────────────┐   ││
                          │  │  │   Application Load Balancer (ALB)        │   ││
                          │  │  │   - HTTP (80) → redirect to HTTPS        │   ││
                          │  │  │   - HTTPS (443) → forward to EC2         │   ││
                          │  │  │   - Health check: GET / every 30s        │   ││
                          │  │  └─────────────────┬────────────────────────┘   ││
                          │  │                    │                              ││
                          │  │  ┌─────────────────▼────────────────────────┐   ││
                          │  │  │        NAT Gateway (outbound only)        │   ││
                          │  │  └──────────────────────────────────────────┘   ││
                          │  └─────────────────────┬───────────────────────────┘│
                          │                        │                             │
                          │  ┌─────────────────────▼───────────────────────────┐│
                          │  │   PRIVATE SUBNETS (10.0.10.0/24, 10.0.11.0/24) ││
                          │  │                                                   ││
                          │  │  ┌──────────────┐   ┌──────────────┐            ││
                          │  │  │  EC2 (AZ-1)  │   │  EC2 (AZ-2)  │ Auto       ││
                          │  │  │  Flask App   │   │  Flask App   │ Scaling    ││
                          │  │  │  Gunicorn    │   │  Gunicorn    │ Group      ││
                          │  │  │  Port 8000   │   │  Port 8000   │ (1–4 inst) ││
                          │  │  └──────┬───────┘   └──────┬───────┘            ││
                          │  │         │                   │                    ││
                          │  │  ┌──────▼───────────────────▼───────────────┐   ││
                          │  │  │          RDS PostgreSQL 15                │   ││
                          │  │  │    (Private, Encrypted, Multi-AZ ready)   │   ││
                          │  │  └──────────────────────────────────────────┘   ││
                          │  └───────────────────────────────────────────────── ┘│
                          │                                                       │
                          │  ┌─────────────────────────────────────────────────┐ │
                          │  │              Supporting Services                  │ │
                          │  │  S3 (images) │ S3 (static) │ ECR │ CloudWatch   │ │
                          │  │  SSM (secrets) │ IAM (roles) │ VPC Flow Logs    │ │
                          │  └─────────────────────────────────────────────────┘ │
                          └─────────────────────────────────────────────────────┘
```

### Key Design Decisions
| Decision | Rationale |
|---|---|
| Flask app in private subnets | Never exposed directly to internet — ALB is the only entry point |
| RDS in private subnets | Database never publicly accessible — EC2 is the only client |
| Secrets in SSM Parameter Store | No env files or hardcoded credentials anywhere |
| IMDSv2 required on EC2 | Prevents SSRF attacks from accessing instance metadata |
| Auto Scaling across 2 AZs | High availability — survives an AZ failure |
| S3 for image uploads | Scalable, durable storage with lifecycle archiving |

---

## 2. Prerequisites

### Install These Tools

```bash
# 1. AWS CLI (v2)
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
aws --version   # Should show 2.x

# 2. Terraform (v1.6+)
brew install terraform
terraform --version

# 3. Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop
docker --version

# 4. Git (already installed)
git --version
```

---

## 3. AWS Account Setup

### Step 3.1: Create IAM User for Deployment

1. Go to **AWS Console → IAM → Users → Create user**
2. Username: `nhce-deployer`
3. Attach policies:
   - `AmazonEC2FullAccess`
   - `AmazonRDSFullAccess`
   - `AmazonS3FullAccess`
   - `AmazonVPCFullAccess`
   - `CloudWatchFullAccess`
   - `AmazonECR_FullAccess`
   - `AWSCodeDeployFullAccess`
   - `IAMFullAccess`
4. Create Access Key → **Download CSV**

### Step 3.2: Configure AWS CLI

```bash
aws configure
# AWS Access Key ID: <from CSV>
# AWS Secret Access Key: <from CSV>
# Default region: ap-south-1
# Default output format: json

# Verify
aws sts get-caller-identity
```

### Step 3.3: Create EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --key-name nhce-laf-keypair \
  --region ap-south-1 \
  --query "KeyMaterial" \
  --output text > ~/.ssh/nhce-laf-keypair.pem

chmod 400 ~/.ssh/nhce-laf-keypair.pem
```

---

## 4. Infrastructure Deployment (Terraform)

### Step 4.1: Set Required Variables

```bash
# Navigate to terraform directory
cd aws/terraform

# Set sensitive variables as environment variables (never commit these!)
export TF_VAR_db_password="YourSecurePassword123!"
export TF_VAR_flask_secret_key="$(openssl rand -hex 32)"
export TF_VAR_mail_password="your-gmail-app-password"

# Optional: override defaults
export TF_VAR_aws_region="ap-south-1"
export TF_VAR_environment="prod"
```

### Step 4.2: Initialize and Plan

```bash
cd aws/terraform

# Initialize Terraform (downloads providers)
terraform init

# Validate configuration
terraform validate

# Preview what will be created
terraform plan
```

**Expected: ~35 resources to create** (VPC, subnets, IGW, NAT, EC2, RDS, S3, ALB, IAM, CloudWatch)

### Step 4.3: Apply Infrastructure

```bash
terraform apply
# Type 'yes' when prompted

# This takes ~10-15 minutes (RDS takes longest)
```

### Step 4.4: View Outputs

```bash
terraform output deployment_summary
terraform output alb_dns_name          # Your app URL
terraform output ecr_docker_push_commands  # Commands to push Docker image
terraform output cloudwatch_dashboard_url  # Monitoring dashboard
```

---

## 5. Docker Build & Push to ECR

```bash
# From project root
cd /path/to/NHCE-LOST_AND_FOUND

# Get ECR URL from Terraform outputs
ECR_URL=$(cd aws/terraform && terraform output -raw ecr_repository_url)
AWS_REGION="ap-south-1"

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URL

# Build the image (from project root, using aws/docker/Dockerfile)
docker build -t nhce-laf-app -f aws/docker/Dockerfile .

# Tag and push
docker tag nhce-laf-app:latest $ECR_URL:latest
docker push $ECR_URL:latest

echo "✅ Image pushed to ECR!"
```

### Test Locally with Docker Compose

```bash
cd aws/docker
docker compose up -d

# Check it's running
docker compose ps

# View logs
docker compose logs -f app

# Open in browser: http://localhost:8000
# pgAdmin: http://localhost:5050 (admin@nhce.edu / admin123)

# Stop
docker compose down
```

---

## 6. CI/CD Pipeline Setup

### Step 6.1: Add GitHub Secrets

1. Go to your repo: `https://github.com/Chandugv/NHCE-LOST_AND_FOUND`
2. Click **Settings → Secrets and variables → Actions → New repository secret**

Add these secrets:

| Secret Name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | From your IAM user CSV |
| `AWS_SECRET_ACCESS_KEY` | From your IAM user CSV |

### Step 6.2: Create GitHub Environment

1. **Settings → Environments → New environment**
2. Name: `production`
3. Add **Required reviewers** (your GitHub username)
4. This adds a manual approval gate before production deploys

### Step 6.3: How the Pipeline Works

```
Push to 'main' branch
        │
        ▼
┌───────────────┐
│  🧪 Test Job  │  Lint (flake8) + smoke test Flask imports
└───────┬───────┘
        │ (on success)
        ▼
┌─────────────────────┐
│  🐳 Build & Push    │  Docker build → ECR push (with git SHA tag)
└──────────┬──────────┘
           │ (manual approval required)
           ▼
┌─────────────────────────┐
│  🚀 Deploy to AWS EC2   │  ASG instance refresh → health check
└─────────────────────────┘
```

### Step 6.4: Manual Trigger

You can trigger a deployment manually:
1. Go to **Actions tab** in your GitHub repo
2. Select **🚀 Deploy to AWS** workflow
3. Click **Run workflow**

---

## 7. CloudWatch Monitoring

### Access Your Dashboard

```bash
# Get the dashboard URL
cd aws/terraform && terraform output cloudwatch_dashboard_url
```

### Dashboard Panels

| Panel | What It Shows |
|---|---|
| 📈 Requests/Minute | Traffic hitting your ALB |
| ❌ HTTP Errors | 4xx and 5xx error counts |
| ⏱️ Response Time | p95 latency of your Flask app |
| 🖥️ EC2 CPU | CPU utilization across all instances |
| ⚖️ Auto Scaling | Current vs desired instance count |
| 🗄️ RDS Database | Connections and DB CPU |
| 💚 Healthy Hosts | Instances passing/failing health checks |
| 📦 S3 Storage | Size of image upload bucket |

### View Live Logs

```bash
# Stream application logs
aws logs tail /nhce-lostandfound/app \
  --region ap-south-1 \
  --follow

# Stream error logs
aws logs tail /nhce-lostandfound/errors \
  --region ap-south-1 \
  --follow

# Search for specific errors
aws logs filter-log-events \
  --log-group-name /nhce-lostandfound/errors \
  --filter-pattern "ERROR" \
  --region ap-south-1
```

### Configured Alarms

| Alarm | Condition | Action |
|---|---|---|
| ALB 5xx Errors | >10 errors/minute | 🔔 Alert |
| RDS Connections | >80 connections | 🔔 Alert |
| RDS Low Storage | <2 GB free | 🔔 Alert |
| Unhealthy Hosts | ≥1 host failing | 🔔 Alert |
| High Latency | p95 >3 seconds | 🔔 Alert |
| CPU Critical | >90% for 3 minutes | 🔔 Alert |
| CPU High (ASG) | >70% for 10 minutes | ⚡ Auto Scale Out |
| CPU Low (ASG) | <30% for 50 minutes | ⚡ Auto Scale In |

---

## 8. Security Overview

### What's Protected

| Threat | Protection |
|---|---|
| DB exposed to internet | RDS in private subnet, SG allows only EC2 on port 5432 |
| Credentials in code | All secrets in SSM Parameter Store, fetched at runtime |
| Unauthorized EC2 access | No port 22 open; use AWS Systems Manager Session Manager |
| Instance metadata attacks | IMDSv2 enforced (requires session token) |
| Insecure images | ECR scan on push, non-root container user |
| Unencrypted data | S3 encryption, RDS encryption, EBS encryption at rest |
| Cross-service abuse | Least-privilege IAM roles per service |
| Network intrusion | VPC Flow Logs enabled for audit trail |

### SSH via Session Manager (No Port 22)

```bash
# Install Session Manager plugin
brew install --cask session-manager-plugin

# Start a session (no port 22 needed)
aws ssm start-session \
  --target <instance-id> \
  --region ap-south-1
```

---

## 9. Troubleshooting Guide

### App Not Responding

```bash
# 1. Check ALB health
aws elbv2 describe-target-health \
  --target-group-arn $(cd aws/terraform && terraform output -raw alb_arn | sed 's/loadbalancer/targetgroup/') \
  --region ap-south-1

# 2. SSH into EC2 and check Docker
aws ssm start-session --target <instance-id> --region ap-south-1
docker ps
docker logs nhce-app --tail 100

# 3. Manual health check
./aws/scripts/health_check.sh

# 4. Restart container
docker restart nhce-app
```

### Database Connection Error

```bash
# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier nhce-laf-postgres \
  --region ap-south-1 \
  --query "DBInstances[0].DBInstanceStatus"

# Check connectivity from EC2
# (via SSM session on EC2)
psql -h <rds-endpoint> -U nhce_admin -d nhce_lostandfound
```

### Deployment Failed

```bash
# 1. Check the CI/CD logs in GitHub Actions tab

# 2. Manual rollback to last working commit
./aws/scripts/rollback.sh --tag <previous-git-sha>

# 3. Check what image tags are available
aws ecr list-images \
  --repository-name nhce-laf-app \
  --region ap-south-1
```

### View All CloudWatch Alarms

```bash
aws cloudwatch describe-alarms \
  --region ap-south-1 \
  --alarm-name-prefix nhce-laf \
  --query "MetricAlarms[*].{Name:AlarmName,State:StateValue}" \
  --output table
```

---

## 10. Cost Estimate

> **Note:** Using Free Tier-eligible resources where possible. Actual costs depend on traffic.

| Service | Resource | Est. Monthly Cost |
|---|---|---|
| EC2 | 2x t3.micro (750h free/month each) | **Free** (1st year) / ~$15 after |
| RDS | db.t3.micro PostgreSQL | **Free** (750h/month, 1st year) / ~$15 after |
| S3 | 5 GB storage + requests | ~$0.12 |
| NAT Gateway | 1x + data transfer | ~$35/month |
| ALB | 1x + LCU usage | ~$18/month |
| CloudWatch | Logs + metrics + alarms | ~$5/month |
| ECR | 500 MB storage | ~$0.05 |
| Data Transfer | Outbound to internet | ~$0.09/GB |

> **💡 Cost Tip:** The biggest cost is the **NAT Gateway (~$35/mo)**. For a student project, you can:
> - Use a NAT Instance (t3.nano, ~$3.50/mo) instead
> - Only run the infrastructure when needed (`terraform destroy` when done)

---

## 11. Learning Topics Covered

| Topic | Where in This Project |
|---|---|
| **Linux Commands** | `user_data.sh` — package installation, file management, systemctl, cron |
| **IP Addresses & Subnets** | `vpc.tf` — CIDR blocks 10.0.0.0/16, /24 subnets, routing |
| **DNS** | VPC DNS hostnames, RDS endpoint, ALB DNS name |
| **TCP/IP** | Security groups — port 80, 443, 8000, 5432 rules |
| **HTTP** | ALB listeners, health checks, HTTP→HTTPS redirect |
| **AWS IAM** | `iam.tf` — roles, policies, instance profiles, SSM secrets |
| **AWS EC2** | `ec2.tf` — launch templates, IMDSv2, EBS volumes |
| **AWS S3** | `s3.tf` — buckets, versioning, encryption, lifecycle |
| **AWS VPC** | `vpc.tf` — subnets, IGW, NAT, route tables, flow logs |
| **AWS RDS** | `rds.tf` — managed PostgreSQL, backups, monitoring |
| **AWS CloudWatch** | `cloudwatch.tf` — dashboards, alarms, log groups |
| **Load Balancing** | `alb.tf` — ALB, target groups, health checks, stickiness |
| **Auto Scaling** | `ec2.tf` — ASG, scaling policies, rolling deployments |
| **High Availability** | 2 AZs, ALB across AZs, ASG min=1 |
| **Git** | `.github/workflows/` — branching, commit-tagged deploys |
| **Docker** | `Dockerfile` — multi-stage, non-root, health checks |
| **Terraform** | Full IaC across all files — providers, modules, outputs |
| **Cloud Security** | IAM least-privilege, IMDSv2, private subnets, encryption |
| **Troubleshooting** | `health_check.sh`, `rollback.sh`, CloudWatch log queries |

---

*Generated for NHCE Cloud Engineering Project — Chandugv/NHCE-LOST_AND_FOUND*

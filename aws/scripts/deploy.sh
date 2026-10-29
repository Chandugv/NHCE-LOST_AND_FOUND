#!/bin/bash
################################################################################
# NHCE Lost & Found — One-Command AWS Deployment Script
# Usage: ./aws/scripts/deploy.sh [--env prod] [--tag latest]
# Prerequisites: AWS CLI, Terraform, Docker installed and configured
################################################################################

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }
ok()   { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "${RED}❌ $1${NC}"; exit 1; }

# ─── Parse Arguments ──────────────────────────────────────────────────────────
ENV="prod"
IMAGE_TAG="latest"
SKIP_TERRAFORM=false
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)        ENV="$2";        shift 2 ;;
    --tag)        IMAGE_TAG="$2";  shift 2 ;;
    --skip-tf)    SKIP_TERRAFORM=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    *) warn "Unknown arg: $1"; shift ;;
  esac
done

# ─── Config ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
AWS_REGION="${AWS_REGION:-ap-south-1}"
PROJECT_NAME="nhce-laf"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    🎒 NHCE Lost & Found — AWS Deployment Script     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo -e "  Environment: ${GREEN}$ENV${NC}"
echo -e "  Image Tag:   ${GREEN}$IMAGE_TAG${NC}"
echo -e "  Region:      ${GREEN}$AWS_REGION${NC}"
echo ""

# ─── Prerequisites Check ──────────────────────────────────────────────────────
log "Checking prerequisites..."

for cmd in aws terraform docker git; do
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd is not installed. See DEPLOYMENT_GUIDE.md for setup."
  fi
done

# Verify AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  err "AWS credentials not configured. Run: aws configure"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ok "AWS Account: $ACCOUNT_ID | Region: $AWS_REGION"

# Check required env vars
: "${TF_VAR_db_password:?Set TF_VAR_db_password}"
: "${TF_VAR_flask_secret_key:?Set TF_VAR_flask_secret_key}"

ok "Prerequisites OK"

# ─── Step 1: Terraform Infrastructure ────────────────────────────────────────
if [ "$SKIP_TERRAFORM" = false ]; then
  log "Step 1/4: Provisioning AWS infrastructure with Terraform..."
  cd "$TERRAFORM_DIR"

  terraform init -upgrade
  terraform validate

  log "Running terraform plan..."
  terraform plan -out=tfplan -var="environment=$ENV"

  echo ""
  read -rp "$(echo -e "${YELLOW}Apply this plan? (yes/no): ${NC}")" CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    warn "Deployment cancelled."
    exit 0
  fi

  terraform apply tfplan
  ok "Infrastructure provisioned!"

  # Extract outputs
  ECR_REPO=$(terraform output -raw ecr_repository_url)
  ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null | sed 's|http://||' | sed 's|:8080||')
else
  log "Skipping Terraform (--skip-tf flag)"
  cd "$TERRAFORM_DIR"
  ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null)
  ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null | sed 's|http://||' | sed 's|:8080||')
fi

# ─── Step 2: Build & Push Docker Image ────────────────────────────────────────
if [ "$SKIP_BUILD" = false ]; then
  log "Step 2/4: Building and pushing Docker image to ECR..."
  cd "$PROJECT_ROOT"

  # Authenticate Docker to ECR
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_REPO"

  # Build the Docker image
  docker build \
    -t "$PROJECT_NAME-app" \
    -f aws/docker/Dockerfile \
    --label "git-commit=$(git rev-parse --short HEAD)" \
    --label "build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    .

  # Tag and push
  docker tag "$PROJECT_NAME-app:latest" "$ECR_REPO:$IMAGE_TAG"
  docker tag "$PROJECT_NAME-app:latest" "$ECR_REPO:latest"
  docker push "$ECR_REPO:$IMAGE_TAG"
  docker push "$ECR_REPO:latest"

  ok "Docker image pushed: $ECR_REPO:$IMAGE_TAG"
else
  log "Skipping Docker build (--skip-build flag)"
fi

# ─── Step 3: Trigger Rolling Deployment ──────────────────────────────────────
log "Step 3/4: Triggering rolling deployment (ASG instance refresh)..."

ASG_NAME="${PROJECT_NAME}-asg"
REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --region "$AWS_REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 60}' \
  --query "InstanceRefreshId" \
  --output text 2>/dev/null || echo "SKIP")

if [ "$REFRESH_ID" = "SKIP" ]; then
  warn "Could not trigger instance refresh. ASG may not exist yet."
else
  log "Instance refresh started: $REFRESH_ID. Monitoring..."

  for i in $(seq 1 20); do
    STATUS=$(aws autoscaling describe-instance-refreshes \
      --region "$AWS_REGION" \
      --auto-scaling-group-name "$ASG_NAME" \
      --instance-refresh-ids "$REFRESH_ID" \
      --query "InstanceRefreshes[0].Status" \
      --output text 2>/dev/null || echo "Unknown")

    log "[$i/20] Status: $STATUS"

    if [ "$STATUS" = "Successful" ]; then
      ok "Rolling deployment complete!"; break
    elif [[ "$STATUS" =~ ^(Failed|Cancelled)$ ]]; then
      err "Deployment $STATUS. Check CloudWatch logs."
    fi
    sleep 30
  done
fi

# ─── Step 4: Health Check ─────────────────────────────────────────────────────
log "Step 4/4: Verifying app health..."

APP_URL="http://$ALB_DNS:8080"
for i in $(seq 1 10); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL" 2>/dev/null || echo "000")
  log "[$i/10] $APP_URL → HTTP $HTTP_CODE"
  if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    ok "App is live!"; break
  fi
  sleep 15
done

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              🎉 Deployment Complete!                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo -e "  🌐 App URL:       ${CYAN}$APP_URL${NC}"
echo -e "  📊 Dashboard:     ${CYAN}https://$AWS_REGION.console.aws.amazon.com/cloudwatch${NC}"
echo -e "  📋 Logs:          ${CYAN}https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home#logsV2${NC}"
echo ""

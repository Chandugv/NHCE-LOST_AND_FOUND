#!/bin/bash
################################################################################
# NHCE Lost & Found — Emergency Rollback Script
# Reverts to a previously working Docker image tag
# Usage: ./aws/scripts/rollback.sh --tag <previous-git-sha>
# Example: ./aws/scripts/rollback.sh --tag abc1234
################################################################################

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }
ok()   { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "${RED}❌ ERROR: $1${NC}"; exit 1; }

# ─── Parse Arguments ──────────────────────────────────────────────────────────
ROLLBACK_TAG=""
AWS_REGION="${AWS_REGION:-ap-south-1}"
PROJECT_NAME="nhce-laf"
ASG_NAME="${PROJECT_NAME}-asg"
ECR_REPO=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --tag)    ROLLBACK_TAG="$2"; shift 2 ;;
    --region) AWS_REGION="$2";  shift 2 ;;
    *) warn "Unknown argument: $1"; shift ;;
  esac
done

# ─── Header ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║         🚨 NHCE Lost & Found — ROLLBACK              ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Confirm rollback
warn "This will roll back the production deployment!"
read -rp "$(echo -e "${RED}Are you sure? Type 'rollback' to confirm: ${NC}")" CONFIRM
[ "$CONFIRM" != "rollback" ] && { warn "Rollback cancelled."; exit 0; }

# ─── Get ECR Repository URL ───────────────────────────────────────────────────
log "Fetching ECR repository URL..."
ECR_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && \
  terraform output -raw ecr_repository_url 2>/dev/null) || \
  err "Could not get ECR repo. Run from project root or set ECR_REPO env var."

# ─── Choose Rollback Tag ──────────────────────────────────────────────────────
if [ -z "$ROLLBACK_TAG" ]; then
  log "Available images in ECR:"
  aws ecr list-images \
    --region "$AWS_REGION" \
    --repository-name "${PROJECT_NAME}-app" \
    --query "imageIds[*].imageTag" \
    --output table 2>/dev/null || warn "Could not list images"

  read -rp "Enter tag to roll back to: " ROLLBACK_TAG
fi

log "Rolling back to tag: ${ROLLBACK_TAG}"

# ─── Verify the Image Exists ──────────────────────────────────────────────────
log "Verifying image exists in ECR..."
aws ecr describe-images \
  --region "$AWS_REGION" \
  --repository-name "${PROJECT_NAME}-app" \
  --image-ids "imageTag=$ROLLBACK_TAG" \
  --output table 2>/dev/null || err "Image tag '$ROLLBACK_TAG' not found in ECR"
ok "Image verified"

# ─── Re-tag as 'latest' in ECR ───────────────────────────────────────────────
log "Re-tagging '$ROLLBACK_TAG' as 'rollback-latest' in ECR..."

# Get the image manifest
MANIFEST=$(aws ecr batch-get-image \
  --region "$AWS_REGION" \
  --repository-name "${PROJECT_NAME}-app" \
  --image-ids "imageTag=$ROLLBACK_TAG" \
  --query "images[0].imageManifest" \
  --output text)

# Put it with the 'latest' tag
aws ecr put-image \
  --region "$AWS_REGION" \
  --repository-name "${PROJECT_NAME}-app" \
  --image-tag "rollback-latest" \
  --image-manifest "$MANIFEST" 2>/dev/null || \
  warn "Could not re-tag (may already exist) — continuing..."

ok "Image re-tagged"

# ─── Trigger Rolling Refresh ──────────────────────────────────────────────────
log "Triggering ASG instance refresh to roll back..."

REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --region "$AWS_REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences '{"MinHealthyPercentage": 100, "InstanceWarmup": 60}' \
  --query "InstanceRefreshId" \
  --output text 2>/dev/null) || \
  warn "Could not start instance refresh. You may need to restart manually."

log "Waiting for rollback to complete..."
for i in $(seq 1 20); do
  STATUS=$(aws autoscaling describe-instance-refreshes \
    --region "$AWS_REGION" \
    --auto-scaling-group-name "$ASG_NAME" \
    --instance-refresh-ids "$REFRESH_ID" \
    --query "InstanceRefreshes[0].Status" \
    --output text 2>/dev/null || echo "Unknown")

  log "[$i/20] Refresh status: $STATUS"

  if [ "$STATUS" = "Successful" ]; then
    ok "Rollback deployment complete!"; break
  elif [[ "$STATUS" =~ ^(Failed|Cancelled)$ ]]; then
    err "Rollback failed: $STATUS. SSH into instances and check Docker logs."
  fi
  sleep 30
done

echo ""
ok "=== ROLLBACK COMPLETE ==="
log "Rolled back to image tag: $ROLLBACK_TAG"
log "Check app health: ./aws/scripts/health_check.sh"
log "View logs: aws logs tail /nhce-lostandfound/errors --region $AWS_REGION --follow"

#!/bin/bash
################################################################################
# NHCE Lost & Found — Health Check Script
# Monitors app health and sends custom metrics to CloudWatch
# Usage: Run on EC2 instance via cron every 30 seconds, or manually
# Cron: */1 * * * * /home/ec2-user/health_check.sh >> /var/log/nhce-app/health.log 2>&1
################################################################################

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
APP_URL="${APP_URL:-http://localhost:8000}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
NAMESPACE="NHCE/LostAndFound"
LOG_FILE="/var/log/nhce-app/health.log"
TIMEOUT=10
INSTANCE_ID=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "local")

# ─── Colors (for terminal output) ────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# ─── Check Application Health ─────────────────────────────────────────────────
log "=== Health Check Starting (Instance: $INSTANCE_ID) ==="

# Measure response time and HTTP status
START_TIME=$(date +%s%N)
HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" \
  --max-time "$TIMEOUT" \
  "$APP_URL/" 2>/dev/null || echo "000|0")

END_TIME=$(date +%s%N)

HTTP_CODE=$(echo "$HTTP_RESPONSE" | cut -d'|' -f1)
RESPONSE_TIME=$(echo "$HTTP_RESPONSE" | cut -d'|' -f2)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

log "HTTP Status: $HTTP_CODE | Response Time: ${RESPONSE_TIME}s (${DURATION_MS}ms)"

# ─── Determine Health Status ──────────────────────────────────────────────────
HEALTH_VALUE=0
HEALTH_STATUS="UNHEALTHY"

if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
  HEALTH_VALUE=1
  HEALTH_STATUS="HEALTHY"
  log "${GREEN}✅ App is HEALTHY${NC}"
else
  HEALTH_STATUS="UNHEALTHY"
  log "${RED}❌ App is UNHEALTHY (HTTP $HTTP_CODE)${NC}"
fi

# ─── Send Metrics to CloudWatch ───────────────────────────────────────────────
if command -v aws &>/dev/null && [ "$INSTANCE_ID" != "local" ]; then

  # 1. Health status (1 = healthy, 0 = unhealthy)
  aws cloudwatch put-metric-data \
    --region "$AWS_REGION" \
    --namespace "$NAMESPACE" \
    --metric-name "AppHealthStatus" \
    --value "$HEALTH_VALUE" \
    --unit "None" \
    --dimensions "InstanceId=$INSTANCE_ID" 2>/dev/null && \
    log "Sent AppHealthStatus=$HEALTH_VALUE to CloudWatch"

  # 2. Response time in milliseconds
  aws cloudwatch put-metric-data \
    --region "$AWS_REGION" \
    --namespace "$NAMESPACE" \
    --metric-name "AppResponseTimeMs" \
    --value "$DURATION_MS" \
    --unit "Milliseconds" \
    --dimensions "InstanceId=$INSTANCE_ID" 2>/dev/null && \
    log "Sent AppResponseTimeMs=$DURATION_MS to CloudWatch"

  # 3. Check Docker container status
  if command -v docker &>/dev/null; then
    CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' nhce-app 2>/dev/null || echo "not_found")
    CONTAINER_RUNNING=0
    [ "$CONTAINER_STATUS" = "running" ] && CONTAINER_RUNNING=1

    aws cloudwatch put-metric-data \
      --region "$AWS_REGION" \
      --namespace "$NAMESPACE" \
      --metric-name "DockerContainerRunning" \
      --value "$CONTAINER_RUNNING" \
      --unit "None" \
      --dimensions "InstanceId=$INSTANCE_ID" 2>/dev/null
    log "Container status: $CONTAINER_STATUS (metric=$CONTAINER_RUNNING)"
  fi

  # 4. System memory usage (%)
  MEM_USED=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100}')
  aws cloudwatch put-metric-data \
    --region "$AWS_REGION" \
    --namespace "$NAMESPACE" \
    --metric-name "MemoryUsedPercent" \
    --value "$MEM_USED" \
    --unit "Percent" \
    --dimensions "InstanceId=$INSTANCE_ID" 2>/dev/null
  log "Memory used: ${MEM_USED}%"

else
  log "AWS CLI not available or running locally — skipping CloudWatch metrics"
fi

# ─── Auto-Restart on Failure ──────────────────────────────────────────────────
if [ "$HEALTH_STATUS" = "UNHEALTHY" ]; then
  log "🔄 Attempting container restart..."
  if command -v docker &>/dev/null; then
    docker restart nhce-app 2>/dev/null && \
      log "Container restarted. Waiting 30s..." && sleep 30

    # Re-check after restart
    RETRY_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$APP_URL/" 2>/dev/null || echo "000")
    if [[ "$RETRY_CODE" =~ ^(200|301|302)$ ]]; then
      log "✅ App recovered after restart (HTTP $RETRY_CODE)"
    else
      log "❌ App still unhealthy after restart (HTTP $RETRY_CODE) — manual intervention needed"
    fi
  fi
fi

log "=== Health Check Complete ==="

################################################################################
# NHCE Lost & Found — Multi-Stage Dockerfile
# Stage 1: Build (install deps)  →  Stage 2: Runtime (slim, secure)
################################################################################

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy and install Python dependencies into a virtual environment
COPY requirements.txt .
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
      -r requirements.txt \
      psycopg2-binary \
      boto3 \
      gunicorn

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# Install only runtime system deps (no build tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user (security best practice)
RUN groupadd -r appuser && useradd -r -g appuser -d /app appuser

WORKDIR /app

# Copy virtual environment from builder stage
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application source code
COPY --chown=appuser:appuser . .

# Create directories for uploads and logs
RUN mkdir -p /app/static/uploads /app/logs && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Flask and Gunicorn environment variables
ENV FLASK_APP=app.py \
    FLASK_ENV=production \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

EXPOSE 8000

# Health check: verify the app is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/ || exit 1

# Start Gunicorn with 4 workers
# --workers: num_cpu * 2 + 1 (4 for t3.micro)
# --threads: for I/O bound workloads
# --bind: listen on all interfaces
CMD ["gunicorn", \
     "--workers", "4", \
     "--threads", "2", \
     "--worker-class", "gthread", \
     "--bind", "0.0.0.0:8000", \
     "--timeout", "120", \
     "--keep-alive", "5", \
     "--access-logfile", "/app/logs/access.log", \
     "--error-logfile", "/app/logs/error.log", \
     "--log-level", "info", \
     "app:app"]

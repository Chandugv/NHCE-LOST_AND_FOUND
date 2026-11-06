# 🎒 NHCE Lost & Found System

A production-grade web application for New Horizon College of Engineering (NHCE) that lets students report and recover lost items. Built with a glassmorphic UI, Smart Matching NLP engine, and a fully automated AWS CI/CD pipeline.

[![CI/CD Pipeline](https://github.com/Chandugv/NHCE-LOST_AND_FOUND/actions/workflows/aws-deploy.yml/badge.svg)](https://github.com/Chandugv/NHCE-LOST_AND_FOUND/actions/workflows/aws-deploy.yml)
[![Python 3.11](https://img.shields.io/badge/python-3.11-blue.svg)](https://www.python.org/)
[![Flask](https://img.shields.io/badge/flask-3.0-green.svg)](https://flask.palletsprojects.com/)
[![Tests](https://img.shields.io/badge/tests-41%20passed-brightgreen)](tests/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Features ✨

| Feature | Description |
|---|---|
| **Smart Matching** | NLP keyword intersection cross-references lost ↔ found reports automatically |
| **Automated Notifications** | Real-time alerts via email (Flask-Mailman/SMTP) and in-app dashboard |
| **Glassmorphic UI** | Dark-blue premium interface with micro-animations |
| **Admin Dashboard** | Moderation panel with analytics charts and CSV export |
| **Karma & Rewards** | Gamification — earn points for returning items, redeem at the campus shop |
| **QR Labelling** | Pre-register valuables with a unique QR code; finders scan to contact owner securely |
| **Image Uploads** | Secure upload & resize pipeline via Pillow + S3 |

---

## Tech Stack 🛠️

- **Backend:** Flask 3.0, Python 3.11, SQLAlchemy, PostgreSQL (prod) / SQLite (dev)
- **Frontend:** HTML5, Vanilla CSS3 (Glassmorphism), JavaScript
- **Email:** Flask-Mailman (Gmail SMTP)
- **Containers:** Docker, Amazon ECR
- **Infrastructure:** Terraform (IaC), AWS (VPC · EC2 · ALB · RDS · S3 · ECR · CloudWatch)
- **CI/CD:** GitHub Actions — Lint → Test → Docker Build → ECR Push → Rolling Deploy

---

## AWS Deployment ☁️

### Architecture Diagram

```
                        ┌─────────────────────────────────────────────────────────────┐
                        │                        AWS ap-south-1 (Mumbai)               │
                        │                                                               │
   Browser / NHCE       │   ┌──────────────┐     ┌──────────────────────────────────┐  │
   Campus Users  ──────►│──►│   Internet   │────►│  Application Load Balancer (ALB) │  │
                        │   │   Gateway    │     │  (Multi-AZ, HTTP:80 → 8000)      │  │
                        │   └──────────────┘     └────────────┬─────────────────────┘  │
                        │                                      │                        │
                        │              ┌───────────────────────┼────────────────────┐   │
                        │              │   Auto Scaling Group  │  (min 1 · max 4)   │   │
                        │              │  ┌────────────────┐  ┌▼───────────────────┐│   │
                        │              │  │  EC2 t3.micro  │  │  EC2 t3.micro      ││   │
                        │              │  │  (AZ-a)        │  │  (AZ-b)            ││   │
                        │              │  │  Gunicorn +    │  │  Gunicorn +        ││   │
                        │              │  │  Flask App     │  │  Flask App         ││   │
                        │              │  └───────┬────────┘  └────────┬───────────┘│   │
                        │              └──────────┼───────────────────┼────────────┘   │
                        │                         │                   │                │
                        │            ┌────────────▼───────────────────▼─────────────┐  │
                        │            │          Private Subnets (10.0.10/11.0/24)    │  │
                        │            │                                               │  │
                        │            │   ┌───────────────────┐  ┌────────────────┐  │  │
                        │            │   │  RDS PostgreSQL    │  │  S3 Bucket     │  │  │
                        │            │   │  db.t3.micro       │  │  (Images)      │  │  │
                        │            │   │  Multi-AZ standby  │  │  (Static)      │  │  │
                        │            │   └───────────────────┘  └────────────────┘  │  │
                        │            └───────────────────────────────────────────────┘  │
                        │                                                               │
                        │   ┌─────────────────────────────────────────────────────┐    │
                        │   │  CloudWatch: Dashboard · 6 Alarms · Log Groups      │    │
                        │   └─────────────────────────────────────────────────────┘    │
                        └─────────────────────────────────────────────────────────────┘

   GitHub Actions CI/CD Pipeline
   ───────────────────────────────
   Push to main → Lint (flake8) → Test (41 pytest cases) →
   Docker Build → ECR Push → ASG Rolling Deploy → Health Check
```

> **Interactive diagram:** [Open in draw.io](https://app.diagrams.net/) and import `aws/architecture.drawio` (see below for export link once deployed).

---

### AWS Services Used

| Service | Purpose | Tier |
|---|---|---|
| **VPC** | Isolated network with public (ALB) and private (EC2 + RDS) subnets across 2 AZs | — |
| **EC2 (t3.micro)** | Runs the Dockerised Flask + Gunicorn app | Free Tier eligible |
| **Auto Scaling Group** | Maintains 1–4 instances; rolling deploys via Instance Refresh | — |
| **Application Load Balancer** | HTTPS termination, health checks, distributes traffic across AZs | — |
| **Amazon ECR** | Stores Docker images pushed by the GitHub Actions pipeline | Free Tier eligible |
| **RDS PostgreSQL (db.t3.micro)** | Managed relational database with automated backups | Free Tier eligible |
| **S3** | Image uploads (private bucket) + static assets (public bucket) | Free Tier eligible |
| **IAM** | EC2 instance profile with least-privilege roles for ECR, S3, SSM, CloudWatch | — |
| **SSM Parameter Store** | Stores secrets (DB password, Flask secret key) — no plaintext env vars | Free |
| **CloudWatch** | 1 dashboard · 6 metric alarms · 3 log groups (app, errors, ALB) | Free Tier eligible |
| **GitHub Actions** | CI/CD: Lint → Test → Build → Push → Deploy (3-job pipeline) | 2 000 min/month free |

---

### Monthly Cost Estimate (Mumbai region, ap-south-1)

> Assumes Free Tier is active (first 12 months). After Free Tier, estimated spend for a **single t3.micro EC2 + db.t3.micro RDS** is ~\$25–35 USD/month.

| Resource | Free Tier | After Free Tier / month |
|---|---|---|
| EC2 t3.micro (750 h) | ✅ Free | ~\$8.50 |
| RDS db.t3.micro (750 h, 20 GB) | ✅ Free | ~\$14.00 |
| ALB (15 LCU) | Partial | ~\$6.00 |
| S3 (5 GB + 20K requests) | ✅ Free | ~\$0.25 |
| ECR (500 MB) | ✅ Free | ~\$0.05 |
| CloudWatch (Basic) | ✅ Free | ~\$0 |
| Data Transfer (1 GB out) | ✅ Free | ~\$0.10 |
| **Total** | **\$0** | **~\$29/month** |

> 💡 Run `terraform destroy` after demoing to avoid charges. All resources are tagged `Project=NHCE-LostAndFound` for easy cost tracking in AWS Cost Explorer.

---

### Deploy Steps

#### Prerequisites
- AWS CLI configured (`aws configure`)
- Terraform ≥ 1.6 installed
- Docker installed and running
- An EC2 Key Pair named `nhce-laf-keypair` (create in AWS Console → EC2 → Key Pairs)

#### 1 — Bootstrap Terraform State (one-time)

```bash
# Create the S3 state bucket and DynamoDB lock table manually first
aws s3 mb s3://nhce-lostandfound-tfstate --region ap-south-1
aws dynamodb create-table \
  --table-name nhce-tf-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1

# Then uncomment the backend block in aws/terraform/main.tf
```

#### 2 — Set Secrets as Environment Variables

```bash
export TF_VAR_db_password="your-strong-db-password"
export TF_VAR_flask_secret_key="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
```

#### 3 — Initialise and Apply

```bash
cd aws/terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform manages **~30 resources** across VPC, EC2, RDS, ALB, S3, ECR, IAM, and CloudWatch.

#### 4 — Add GitHub Secrets for the Pipeline

In your repo → Settings → Secrets and variables → Actions, add:

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | From IAM user with ECR + EC2 + ELB permissions |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret |

#### 5 — Push and Watch the Pipeline

```bash
git push origin main
# GitHub Actions tab → "Deploy to AWS" → watch Lint → Test → Build → Deploy
```

#### 6 — Destroy When Done

```bash
cd aws/terraform
terraform destroy
```

---

## CI/CD Pipeline 🔄

```
Push to main
     │
     ▼
┌─────────────────────────────┐
│  Job 1: Lint & Test         │
│  • flake8 syntax check      │
│  • 41 pytest cases          │  ← tests/ folder
│    (SQLite in-memory, ~2 s) │
└────────────┬────────────────┘
             │ pass
             ▼
┌─────────────────────────────┐
│  Job 2: Build & Push        │
│  • docker build             │
│  • Push to Amazon ECR       │
│  • Trivy vulnerability scan │
└────────────┬────────────────┘
             │ pass (main only)
             ▼
┌─────────────────────────────┐
│  Job 3: Rolling Deploy      │
│  • ASG Instance Refresh     │
│  • Wait for Successful      │
│  • ALB health check         │
└─────────────────────────────┘
```

Workflow file: [`.github/workflows/aws-deploy.yml`](.github/workflows/aws-deploy.yml)

---

## Tests 🧪

```bash
# Run the full suite (41 tests, ~2 s, no external dependencies)
python -m pytest tests/ -v
```

| Test file | What it covers |
|---|---|
| [`tests/test_routes.py`](tests/test_routes.py) | Health check, homepage, 404s, login/logout, auth guards, item CRUD |
| [`tests/test_models.py`](tests/test_models.py) | Smart Matching algorithm, password hashing, `allowed_file`, item model |

All tests use an **in-memory SQLite** database — no Postgres, no network, no secrets required in CI.

---

## Local Setup 🚀

```bash
# 1. Clone
git clone https://github.com/Chandugv/NHCE-LOST_AND_FOUND.git
cd NHCE-LOST_AND_FOUND

# 2. Virtual environment
python3 -m venv venv
source venv/bin/activate       # Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Environment variables
cp .env.example .env           # then edit .env with your Gmail App Password

# 5. Run
python init_db.py
python app.py
# → http://127.0.0.1:5000/
```

---

## Project Structure 📁

```
NHCE-LOST_AND_FOUND/
├── app.py                  # Flask application & all routes
├── models.py               # SQLAlchemy models (User, Item, Claim, …)
├── config.py               # Configuration with env-var overrides
├── requirements.txt
├── tests/                  # pytest test suite
│   ├── conftest.py         # Fixtures & helper factories
│   ├── test_routes.py      # Route / integration tests
│   └── test_models.py      # Business logic unit tests
├── aws/
│   ├── terraform/          # Full IaC — VPC, EC2, ALB, RDS, S3, CloudWatch
│   ├── docker/             # Dockerfile & docker-compose
│   ├── scripts/            # deploy.sh, rollback.sh, health_check.sh
│   └── DEPLOYMENT_GUIDE.md
├── .github/
│   └── workflows/
│       └── aws-deploy.yml  # CI/CD pipeline (Lint → Test → Build → Deploy)
├── templates/              # Jinja2 HTML templates
└── static/                 # CSS, images
```

---

## Screenshots 📸

> _Screenshots of the CloudWatch dashboard, ALB health checks, and a green Actions run will be added after `terraform apply` is run. See the [Deployment Guide](aws/DEPLOYMENT_GUIDE.md) for instructions._

---

## Deployment Checklist

- [x] Terraform IaC for all AWS resources
- [x] GitHub Actions pipeline — Lint → Test → Build → ECR Push → Rolling Deploy
- [x] 41 pytest cases covering routes, models, and smart matching
- [x] CloudWatch dashboard with 6 metric alarms
- [ ] Live URL — pending `terraform apply`
- [ ] Screenshots (CloudWatch, ALB, Actions run)
- [ ] Resume metrics (deploy time, # Terraform resources, # alarms)

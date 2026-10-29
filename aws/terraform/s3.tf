################################################################################
# NHCE Lost & Found — S3 Buckets
# 1. Image uploads bucket (private, versioned)
# 2. Static assets bucket (CSS, JS, fonts)
################################################################################

# Random suffix to ensure globally unique bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ─── Image Uploads Bucket ─────────────────────────────────────────────────────

resource "aws_s3_bucket" "images" {
  bucket        = "${var.project_name}-images-${random_id.bucket_suffix.hex}"
  force_destroy = false  # Prevent accidental deletion

  tags = { Name = "Lost&Found Image Uploads", Purpose = "user-uploads" }
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — images served via pre-signed URLs or through app
resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy: archive old uploads to Glacier after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "archive-old-uploads"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# CORS config: allow Flask app to upload/download directly
resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]   # Tighten to your domain in production
    max_age_seconds = 3000
  }
}

# ─── Static Assets Bucket ─────────────────────────────────────────────────────

resource "aws_s3_bucket" "static" {
  bucket        = "${var.project_name}-static-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = { Name = "Lost&Found Static Assets", Purpose = "static-hosting" }
}

resource "aws_s3_bucket_website_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  index_document { suffix = "index.html" }
  error_document { key    = "error.html" }
}

# Allow public read for CSS, JS, images
resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "static_public_read" {
  bucket     = aws_s3_bucket.static.id
  depends_on = [aws_s3_bucket_public_access_block.static]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.static.arn}/*"
    }]
  })
}

# ─── Terraform State Bucket (Bootstrap — create manually first) ──────────────
# Instructions in DEPLOYMENT_GUIDE.md — uncomment after manual creation
# resource "aws_s3_bucket" "tfstate" {
#   bucket = "nhce-lostandfound-tfstate"
#   ...
# }

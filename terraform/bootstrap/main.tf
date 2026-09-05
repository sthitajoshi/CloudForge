# Day 3: one-time bootstrap — creates the S3 bucket + DynamoDB lock table
# that every env's remote backend depends on. This can't manage its own
# state remotely (chicken-and-egg), so it stays local-state, apply once,
# and rarely touch again.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3       = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "cloudforge-tf-state"

  tags = {
    Name        = "cloudforge-tf-state"
    Environment = "shared"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# State files name every resource in the environment. Nothing about this
# bucket should ever be reachable publicly.
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Every apply writes a new state version. Keeping them forever is how this
# bucket becomes the largest thing in the account; 90 days is enough to
# recover from a bad apply.
resource "aws_s3_bucket_lifecycle_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "cloudforge-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # A lost lock table means a stuck apply, not lost data -- but recovering
  # it by hand during an incident is worse than paying for the backup.
  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "cloudforge-tf-lock"
    Environment = "shared"
  }
}

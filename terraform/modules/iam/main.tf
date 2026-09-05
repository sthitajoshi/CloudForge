# Two roles, both least-privilege. Every Action is named explicitly and
# every Resource is a concrete ARN — no "*" appears anywhere in this file,
# which is the property the Checkov policy in terraform/policy enforces.

# ---------------------------------------------------------------------------
# App role — assumed by the workload, reads one bucket and nothing else.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "app" {
  name = "${var.env}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.env}-app-role"
    Environment = var.env
  }
}

# The two-statement split is deliberate and is the part people get wrong:
# object-level actions (GetObject) target objects INSIDE the bucket, so the
# ARN ends in "/*". Bucket-level actions (ListBucket) target the bucket
# itself, so the ARN has no "/*". Collapsing these into one statement either
# over-grants or silently fails.
resource "aws_iam_policy" "app_s3_read" {
  name        = "${var.env}-app-s3-read"
  description = "Read-only access to the ${var.env} application bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::${var.app_bucket_name}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.app_bucket_name}"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_s3_read" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app_s3_read.arn
}

# ---------------------------------------------------------------------------
# CI role — what the pipeline assumes to run terraform. Scoped to exactly
# the state bucket and lock table, so a compromised pipeline cannot read
# application data or touch unrelated infrastructure.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ci" {
  name = "${var.env}-ci-role"

  # Against real AWS this trust policy would name the GitHub OIDC provider
  # instead of an account principal, so no long-lived keys ever exist in CI.
  # LocalStack does not emulate the OIDC federation flow, so the local build
  # trusts the account root and the OIDC variant is documented in the README.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:aws:iam::${var.trusted_account_id}:root" }
    }]
  })

  tags = {
    Name        = "${var.env}-ci-role"
    Environment = var.env
  }
}

resource "aws_iam_policy" "ci_state_access" {
  name        = "${var.env}-ci-state-access"
  description = "Terraform state bucket and lock table access for ${var.env} CI"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::${var.state_bucket_name}/${var.env}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.state_bucket_name}"]
      },
      {
        # These four are exactly what the DynamoDB state lock needs —
        # nothing more. Terraform writes a lock item, reads it to check
        # ownership, and deletes it on release.
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = ["arn:aws:dynamodb:${var.region}:${var.trusted_account_id}:table/${var.lock_table_name}"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ci_state_access" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci_state_access.arn
}

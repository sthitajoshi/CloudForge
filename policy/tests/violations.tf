# Deliberately non-compliant. Used to prove the gate rejects real mistakes.
resource "aws_s3_bucket" "leaky" {
  bucket = "cloudforge-public-data"
}

resource "aws_s3_bucket_acl" "leaky" {
  bucket = aws_s3_bucket.leaky.id
  acl    = "public-read"
}

resource "aws_iam_policy" "too_broad" {
  name = "allow-everything"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
  })
}

resource "aws_eks_node_group" "oversized" {
  cluster_name    = "whatever"
  node_group_name = "oversized"
  node_role_arn   = "arn:aws:iam::000000000000:role/none"
  subnet_ids      = []
  instance_types  = ["m5.24xlarge"]
  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }
}

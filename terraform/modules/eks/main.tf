# Production path — written against the real AWS provider schema and
# validated, but never applied. The local build runs the same workloads on
# kind instead, because an EKS control plane bills ~$73/month with no free
# tier whether or not anything is running on it.
#
# To use this for real: call it from an env root with real credentials and
# no `endpoints` block in the provider. Nothing else in the module changes.

resource "aws_iam_role" "cluster" {
  name = "${var.env}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.env}-eks-cluster-role"
    Environment = var.env
  }
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node" {
  name = "${var.env}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.env}-eks-node-role"
    Environment = var.env
  }
}

# The three AWS-managed policies a node group genuinely requires: join the
# cluster, run the VPC CNI, and pull images from ECR.
resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Kubernetes Secrets are only base64-encoded in etcd by default. This key
# encrypts them at rest, so reading the etcd volume is not enough to read
# every credential in the cluster.
resource "aws_kms_key" "secrets" {
  description             = "Envelope encryption for ${var.env} EKS secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  # Without an explicit policy a KMS key falls back to a default that is
  # broader than it looks. Resource is "*" in every key policy -- it means
  # "this key" and cannot name anything else -- so the scoping has to come
  # from the actions and principals instead.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "KeyAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
        ]
        Resource = "*"
      },
      {
        Sid       = "AllowEKSEnvelopeEncryption"
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name        = "${var.env}-eks-secrets"
    Environment = var.env
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.env}-eks-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_eks_cluster" "this" {
  name     = "${var.env}-cloudforge"
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
    resources = ["secrets"]
  }

  # All five log types. Turning any of them off is the kind of thing a
  # policy check should catch, not something a reviewer has to notice.
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  tags = {
    Name        = "${var.env}-cloudforge"
    Environment = var.env
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.env}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.instance_types

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name        = "${var.env}-default"
    Environment = var.env
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

# Week 1 Review — Networking & State Notes

## VPC design decisions
- 2 AZs, one public + one private subnet per AZ — enough to demonstrate
  multi-AZ patterns without overbuilding for a local/demo project.
- Public subnets get a route table with a default route (0.0.0.0/0) to
  an Internet Gateway.
- Private subnets get their own route table with **no NAT gateway route**.
  NAT gateways bill hourly + per-GB with no free tier on real AWS — one
  of the two resources this project avoids by design (the other is the
  EKS control plane, replaced by kind). Noted so it reads as a deliberate
  cost decision, not a missing feature.

## Remote state
- State backend: S3 bucket `cloudforge-tf-state` + DynamoDB table
  `cloudforge-tf-lock`, both created once via `terraform/bootstrap`
  (kept as local state — can't depend on the backend it creates).
- Why remote state + locking: prevents two applies (two people, or a
  person + CI) from corrupting state concurrently. DynamoDB's
  conditional writes on the `LockID` key implement the lock — a second
  `apply` blocks until the first releases it.
- Why directory-per-environment instead of Terraform workspaces:
  cleaner blast-radius isolation — a mistake in dev's `.tfvars` or
  module call can't touch prod's state file. Workspaces share the same
  backend key prefix and are easier to fat-finger across.

## LocalStack vs real AWS
- Every resource above (`aws_vpc`, `aws_subnet`, `aws_s3_bucket`, etc.)
  uses the real AWS provider — only the `endpoints` block and dummy
  `test`/`test` credentials differ. Swapping to a real AWS account
  is: remove the `endpoints` block, use real credentials/OIDC.

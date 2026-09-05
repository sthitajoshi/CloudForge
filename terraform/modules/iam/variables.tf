variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "AWS region, used to build resource ARNs"
  type        = string
  default     = "us-east-1"
}

variable "trusted_account_id" {
  description = "Account ID trusted to assume the CI role. LocalStack's default account is 000000000000."
  type        = string
  default     = "000000000000"
}

variable "app_bucket_name" {
  description = "Bucket the app role may read from"
  type        = string
}

variable "state_bucket_name" {
  description = "Terraform state bucket the CI role may access"
  type        = string
  default     = "cloudforge-tf-state"
}

variable "lock_table_name" {
  description = "DynamoDB lock table the CI role may access"
  type        = string
  default     = "cloudforge-tf-lock"
}

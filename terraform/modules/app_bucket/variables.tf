variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "bucket_name" {
  description = "Name of the bucket"
  type        = string
}

variable "noncurrent_version_expiration_days" {
  description = "Days before a superseded object version is deleted"
  type        = number
  default     = 30
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the control plane and nodes run in"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "EKS control plane version"
  type        = string
  default     = "1.31"
}

variable "instance_types" {
  description = "Node instance types. Kept to the approved list the policy gate enforces."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_size" {
  description = "Desired node count"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum node count"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum node count"
  type        = number
  default     = 4
}

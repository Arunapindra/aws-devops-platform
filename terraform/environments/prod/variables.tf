variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "aws-devops-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

variable "ecr_repository_names" {
  description = "ECR repository names to create"
  type        = list(string)
  default     = ["api", "frontend", "worker"]
}

variable "manage_aws_auth" {
  description = "Manage aws-auth ConfigMap"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

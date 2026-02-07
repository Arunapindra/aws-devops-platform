###############################################################################
# Staging Environment - aws-devops-platform
# Mirrors prod architecture at reduced scale
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.40" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.27" }
    tls        = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption - staging"
  deletion_window_in_days = 14
  enable_key_rotation     = true
}

module "vpc" {
  source      = "../../modules/vpc"
  project     = var.project
  environment = var.environment
  vpc_cidr    = "10.1.0.0/16"

  enable_nat_gateway      = true
  single_nat_gateway      = true
  enable_flow_logs        = true
  flow_log_retention_days = 30
  additional_tags         = var.additional_tags
}

module "eks" {
  source             = "../../modules/eks"
  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  kubernetes_version = var.kubernetes_version

  cluster_enabled_log_types  = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_days = 30
  cluster_encryption_key_arn = aws_kms_key.eks.arn

  node_groups = {
    general = {
      instance_types = ["m5.large", "m5.xlarge"]
      desired_size   = 2
      min_size       = 2
      max_size       = 6
      capacity_type  = "ON_DEMAND"
      disk_size      = 50
      labels         = { workload = "general", tier = "staging" }
    }
  }

  manage_aws_auth = var.manage_aws_auth
  additional_tags = var.additional_tags
}

module "ecr" {
  source               = "../../modules/ecr"
  project              = var.project
  environment          = var.environment
  repository_names     = var.ecr_repository_names
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  max_image_count      = 20
  force_delete         = false
  create_kms_key       = true
  additional_tags      = var.additional_tags
}

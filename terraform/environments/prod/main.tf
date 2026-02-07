###############################################################################
# Production Environment - aws-devops-platform
# HA configuration: multi-AZ NAT, larger nodes, KMS encryption
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
  description             = "KMS key for EKS secrets encryption - prod"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

module "vpc" {
  source      = "../../modules/vpc"
  project     = var.project
  environment = var.environment
  vpc_cidr    = "10.2.0.0/16"

  enable_nat_gateway      = true
  single_nat_gateway      = false # HA: one NAT per AZ
  enable_flow_logs        = true
  flow_log_retention_days = 90
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
  cluster_log_retention_days = 90
  cluster_encryption_key_arn = aws_kms_key.eks.arn

  node_groups = {
    general = {
      instance_types = ["m5.xlarge", "m5.2xlarge"]
      desired_size   = 3
      min_size       = 3
      max_size       = 10
      capacity_type  = "ON_DEMAND"
      disk_size      = 100
      labels         = { workload = "general", tier = "production" }
    }
    compute = {
      instance_types = ["c5.xlarge", "c5.2xlarge"]
      desired_size   = 2
      min_size       = 2
      max_size       = 8
      capacity_type  = "ON_DEMAND"
      disk_size      = 100
      labels         = { workload = "compute-intensive", tier = "production" }
    }
  }

  manage_aws_auth = var.manage_aws_auth
  additional_tags = merge(var.additional_tags, { Compliance = "soc2" })
}

module "ecr" {
  source               = "../../modules/ecr"
  project              = var.project
  environment          = var.environment
  repository_names     = var.ecr_repository_names
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  max_image_count      = 30
  force_delete         = false
  create_kms_key       = true
  additional_tags      = var.additional_tags
}

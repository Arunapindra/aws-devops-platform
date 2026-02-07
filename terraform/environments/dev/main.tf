###############################################################################
# Dev Environment - aws-devops-platform
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
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

locals {
  name_prefix = "${var.project}-${var.environment}"
}

module "vpc" {
  source      = "../../modules/vpc"
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr

  enable_nat_gateway      = true
  single_nat_gateway      = true
  enable_flow_logs        = true
  flow_log_retention_days = 14
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

  cluster_enabled_log_types  = ["api", "audit", "authenticator"]
  cluster_log_retention_days = 14

  node_groups = {
    general = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      capacity_type  = "ON_DEMAND"
      disk_size      = 30
      labels         = { workload = "general", tier = "dev" }
    }
    spot = {
      instance_types = ["t3.medium", "t3.large"]
      desired_size   = 1
      min_size       = 0
      max_size       = 3
      capacity_type  = "SPOT"
      disk_size      = 30
      labels         = { workload = "batch", tier = "dev" }
    }
  }

  manage_aws_auth = var.manage_aws_auth
  additional_tags = var.additional_tags
}

module "ecr" {
  source           = "../../modules/ecr"
  project          = var.project
  environment      = var.environment
  repository_names = var.ecr_repository_names
  scan_on_push     = true
  max_image_count  = 15
  force_delete     = true
  additional_tags  = var.additional_tags
}

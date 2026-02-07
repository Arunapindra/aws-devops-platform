###############################################################################
# ECR Module
# Creates ECR repositories with image scanning, lifecycle policies,
# and KMS encryption.
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = merge(var.additional_tags, {
    Module = "ecr"
  })
}

###############################################################################
# KMS Key for ECR Encryption
###############################################################################

resource "aws_kms_key" "ecr" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for ECR repository encryption - ${local.name_prefix}"
  deletion_window_in_days = 14
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-kms"
  })
}

resource "aws_kms_alias" "ecr" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${local.name_prefix}-ecr"
  target_key_id = aws_kms_key.ecr[0].key_id
}

###############################################################################
# ECR Repositories
###############################################################################

resource "aws_ecr_repository" "main" {
  for_each = toset(var.repository_names)

  name                 = "${local.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  dynamic "encryption_configuration" {
    for_each = var.create_kms_key ? [1] : []
    content {
      encryption_type = "KMS"
      kms_key         = aws_kms_key.ecr[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}/${each.value}"
    Repository = each.value
  })
}

###############################################################################
# Lifecycle Policy - Keep last N images
###############################################################################

resource "aws_ecr_lifecycle_policy" "main" {
  for_each = toset(var.repository_names)

  repository = aws_ecr_repository.main[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release", "main", "develop"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

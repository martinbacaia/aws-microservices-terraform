###############################################################################
# ECR repository with lifecycle policy and optional cross-account pull policy.
###############################################################################

locals {
  base_tags = merge(
    {
      "Name"      = var.name
      "Module"    = "ecr-repo"
      "ManagedBy" = "terraform"
    },
    var.tags,
  )

  encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
}

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = local.encryption_type
    kms_key         = var.kms_key_arn
  }

  tags = local.base_tags
}

###############################################################################
# Lifecycle policy.
#
# Two rules, evaluated in order (lower rulePriority wins):
#  1. Keep the last N images that match a tag prefix list (versioned releases).
#  2. Expire untagged images after `untagged_image_expiry_days`.
###############################################################################
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_tagged_images} tagged images matching configured prefixes"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = var.tagged_image_prefixes
          countType     = "imageCountMoreThan"
          countNumber   = var.max_tagged_images
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      },
    ]
  })
}

###############################################################################
# Cross-account pull policy (optional).
###############################################################################
data "aws_iam_policy_document" "pull" {
  count = length(var.additional_pull_principals) > 0 ? 1 : 0

  statement {
    sid    = "AllowPullFromAdditionalPrincipals"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.additional_pull_principals
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
  }
}

resource "aws_ecr_repository_policy" "this" {
  count = length(var.additional_pull_principals) > 0 ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = data.aws_iam_policy_document.pull[0].json
}

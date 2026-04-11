# ============================================================================
# Module: <module-name>
# Description: <what this module provisions>
# ============================================================================

# ── versions.tf ─────────────────────────────────────────────────────────────
# Pin provider and module versions for reproducible applies.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Replace with the provider(s) your module needs
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ── variables.tf ────────────────────────────────────────────────────────────
# Every variable must have a description and type.
# Use validation blocks for constrained values.

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "name" {
  description = "Name prefix for all resources created by this module"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,28}[a-z0-9]$", var.name))
    error_message = "Name must be 4-30 chars, lowercase alphanumeric and hyphens, start with letter, end with alphanumeric."
  }
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

# ── locals.tf ───────────────────────────────────────────────────────────────
# Computed values used across resources.

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "iac"
    Module      = "<module-name>"
  })
}

# ── main.tf ─────────────────────────────────────────────────────────────────
# Resource definitions go here.
# Keep resources logically grouped and commented.

# resource "aws_<type>" "main" {
#   name = "${var.name}-${var.environment}"
#   tags = local.common_tags
#   ...
# }

# ── outputs.tf ──────────────────────────────────────────────────────────────
# Every output must have a description.
# Mark sensitive outputs with sensitive = true.

# output "resource_id" {
#   description = "The ID of the provisioned resource"
#   value       = aws_<type>.main.id
# }

# output "resource_arn" {
#   description = "The ARN of the provisioned resource"
#   value       = aws_<type>.main.arn
# }

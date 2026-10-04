terraform {
  required_version = ">= 1.10, < 2.0"
  backend "azurerm" {}
  required_providers {
    github = { source = "integrations/github", version = "~> 6.0" }
  }
}
provider "github" { owner = "JeffCousineau" }
resource "github_branch_protection_v3" "main" {
  for_each                        = { NetValue = "Application checks", NetValue-deployment = "Terraform checks" }
  repository                      = each.key
  branch                          = "main"
  enforce_admins                  = true
  require_conversation_resolution = true
  required_status_checks {
    strict = true
    checks = ["${each.value}:15368"] # GitHub Actions app, confirmed from successful CI runs.
  }
  required_pull_request_reviews {
    required_approving_review_count = 0 # Solo maintainer: PR and checks required, no unavailable second reviewer.
    dismiss_stale_reviews           = true
  }
}
resource "github_repository_environment" "production" {
  repository          = "NetValue-deployment"
  environment         = "production"
  can_admins_bypass   = false
  prevent_self_review = false # The sole maintainer must be able to approve their own deployment.
  reviewers { users = [8643172] }
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}
resource "github_repository_environment_deployment_policy" "main" {
  repository     = github_repository_environment.production.repository
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"
}

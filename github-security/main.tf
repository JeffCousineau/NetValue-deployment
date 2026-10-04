terraform {
  required_version = ">= 1.10, < 2.0"
  backend "azurerm" {}
  required_providers {
    github = { source = "integrations/github", version = "~> 6.0" }
  }
}
provider "github" { owner = "JeffCousineau" }
resource "github_repository_ruleset" "main" {
  for_each    = { NetValue = "Application checks", NetValue-deployment = "Terraform checks" }
  name        = "Protected main"
  repository  = each.key
  target      = "branch"
  enforcement = "active"
  # No bypass actors: these rules apply to the repository owner too.
  conditions {
    ref_name {
      include = ["refs/heads/main"]
      exclude = []
    }
  }
  rules {
    deletion         = true
    non_fast_forward = true
    pull_request {
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      required_review_thread_resolution = true
    }
    required_status_checks {
      strict_required_status_checks_policy = true
      required_check {
        context        = each.value
        integration_id = 15368
      }
    }
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

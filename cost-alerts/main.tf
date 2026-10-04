terraform {
  required_version = ">= 1.10, < 2.0"
  backend "azurerm" {}
  required_providers {
    azapi = { source = "Azure/azapi", version = "~> 2.13" }
  }
}
provider "azapi" {
  subscription_id = "0bc9dd71-16c4-428e-8160-8a90c7c892f5"
  tenant_id       = "e099407c-b3b3-45aa-868e-cc901f513dc5"
}
variable "contact_emails" {
  type      = list(string)
  sensitive = true
}
variable "contact_roles" {
  type    = list(string)
  default = []
}
variable "contact_groups" {
  type    = list(string)
  default = []
}
variable "budget_amount" {
  type    = number
  default = 20
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be positive."
  }
}
variable "budget_start" {
  type    = string
  default = "2026-10-01T00:00:00Z"
}
variable "budget_end" {
  type    = string
  default = "2028-09-30T00:00:00Z"
}
locals {
  alerts = {
    actual_GreaterThan_50_Percent = { threshold = 50, type = "Actual", operator = "GreaterThan" }
    netValue_Actual_1_Percent     = { threshold = 1, type = "Actual", operator = "GreaterThanOrEqualTo" }
    netValue_Actual_5_Percent     = { threshold = 5, type = "Actual", operator = "GreaterThanOrEqualTo" }
    netValue_Actual_100_Percent   = { threshold = 100, type = "Actual", operator = "GreaterThanOrEqualTo" }
    netValue_Forecast_100_Percent = { threshold = 100, type = "Forecasted", operator = "GreaterThanOrEqualTo" }
  }
}
resource "azapi_resource" "budget" {
  type      = "Microsoft.Consumption/budgets@2024-08-01"
  name      = "Monthly_NetValue"
  parent_id = "/subscriptions/0bc9dd71-16c4-428e-8160-8a90c7c892f5"
  body = {
    properties = {
      amount     = var.budget_amount
      category   = "Cost"
      timeGrain  = "Monthly"
      timePeriod = { startDate = var.budget_start, endDate = var.budget_end }
      filter     = {}
      notifications = { for name, alert in local.alerts : name => {
        enabled       = true
        operator      = alert.operator
        threshold     = alert.threshold
        thresholdType = alert.type
        contactEmails = var.contact_emails
        contactRoles  = var.contact_roles
        contactGroups = var.contact_groups
        locale        = "fr-fr"
      } }
    }
  }
  response_export_values = []
  # Azure's concurrency token changes independently of the budget settings.
  ignore_body_changes = ["eTag"]
  lifecycle {
    prevent_destroy = true

  }
}

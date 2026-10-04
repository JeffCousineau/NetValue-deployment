terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" } }
}
provider "azurerm" {
  features {}
  subscription_id                 = "0bc9dd71-16c4-428e-8160-8a90c7c892f5"
  resource_provider_registrations = "none"
}
variable "runner_ip" {
  type = string
  validation {
    condition     = can(cidrnetmask("${var.runner_ip}/32")) && var.runner_ip != "0.0.0.0"
    error_message = "Supply one public IPv4 address; broad AllowAzureServices is prohibited."
  }
}
variable "rule_name" {
  type    = string
  default = "netvalue-terraform-owner"
  validation {
    condition     = can(regex("^(github-[0-9]+|netvalue-terraform-owner)$", var.rule_name))
    error_message = "Use an isolated temporary owner or GitHub runner rule."
  }
}
resource "azurerm_mssql_firewall_rule" "runner" {
  name             = var.rule_name
  server_id        = "/subscriptions/0bc9dd71-16c4-428e-8160-8a90c7c892f5/resourceGroups/rg-netvalue-free/providers/Microsoft.Sql/servers/netvalue-0620db8f-sql"
  start_ip_address = var.runner_ip
  end_ip_address   = var.runner_ip
}
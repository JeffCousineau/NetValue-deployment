terraform {
  required_version = ">= 1.10, < 2.0"
  backend "azurerm" {}
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azapi   = { source = "Azure/azapi", version = "~> 2.0" }
  }
}
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
}
provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

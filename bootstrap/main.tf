terraform {
  backend "local" { path = "../../NetValue-private/bootstrap.tfstate" }
  required_version = ">= 1.10, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azapi   = { source = "Azure/azapi", version = "~> 2.13" }
  }
}
provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
resource "azurerm_resource_provider_registration" "required" {
  for_each = toset(["Microsoft.Storage", "Microsoft.Web", "Microsoft.Sql"])
  name     = each.value
  lifecycle { prevent_destroy = true }
}
resource "azurerm_resource_group" "state" {
  name     = "rg-netvalue-state"
  location = "canadacentral"
  lifecycle { prevent_destroy = true }
}
resource "azurerm_storage_account" "state" {
  name                            = local.storage
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  depends_on                      = [azurerm_resource_provider_registration.required]
  lifecycle { prevent_destroy = true }
}
# Management-plane creation avoids requiring newly assigned data-plane RBAC to propagate.
resource "azapi_resource" "container" {
  type                   = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  parent_id              = "${azurerm_storage_account.state.id}/blobServices/default"
  name                   = "tfstate"
  body                   = { properties = { publicAccess = "None" } }
  response_export_values = []
  lifecycle { prevent_destroy = true }
}
resource "azurerm_role_assignment" "owner_state" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.owner_object_id
}
output "storage_account_name" { value = azurerm_storage_account.state.name }
variable "subscription_id" { default = "0bc9dd71-16c4-428e-8160-8a90c7c892f5" }
variable "tenant_id" { default = "e099407c-b3b3-45aa-868e-cc901f513dc5" }
variable "owner_object_id" { default = "1112bb2c-81d0-4e08-8009-4eab2c6a9b8b" }
locals {
  suffix  = substr(sha256(var.subscription_id), 0, 8)
  name    = "netvalue-${local.suffix}"
  storage = "nvstate${local.suffix}"
}
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}
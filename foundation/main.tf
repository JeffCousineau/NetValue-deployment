terraform {
  required_version = ">= 1.10, < 2.0"
  backend "azurerm" {}
  required_providers {
    time    = { source = "hashicorp/time", version = "~> 0.13" }
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.0" }
  }
}
provider "azuread" { tenant_id = var.tenant_id }
resource "azurerm_resource_group" "app" {
  name     = "rg-netvalue-free"
  location = "canadacentral"
  lifecycle { prevent_destroy = true }
}
resource "azuread_application_registration" "deployment" {
  display_name                   = "NetValue GitHub deployment ${local.suffix}"
  requested_access_token_version = 1
}
resource "azuread_service_principal" "deployment" {
  client_id = azuread_application_registration.deployment.client_id
}
resource "azuread_application_federated_identity_credential" "production" {
  application_id = azuread_application_registration.deployment.id
  display_name   = "github-production"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:JeffCousineau@8643172/NetValue-deployment@1403790853:environment:production"
}
resource "azurerm_role_assignment" "deployment_app" {
  scope                = azurerm_resource_group.app.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployment.object_id
}
resource "azurerm_role_assignment" "deployment_state" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/rg-netvalue-state/providers/Microsoft.Storage/storageAccounts/${local.storage}/blobServices/default/containers/tfstate"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.deployment.object_id
}
resource "azuread_application_registration" "signin" {
  display_name                   = "NetValue"
  sign_in_audience               = "AzureADMyOrg"
  requested_access_token_version = 1
}
resource "azuread_service_principal" "signin" {
  client_id = azuread_application_registration.signin.client_id
}
resource "azuread_application_redirect_uris" "signin" {
  application_id = azuread_application_registration.signin.id
  type           = "Web"
  redirect_uris = [
    "https://${local.name}.azurewebsites.net/signin-oidc",
    "https://${local.name}.azurewebsites.net/signout-callback-oidc",
    "http://localhost:62645/signin-oidc",
    "http://localhost:62645/signout-callback-oidc"
  ]
}
resource "azuread_application_password" "signin" {
  application_id      = azuread_application_registration.signin.id
  display_name        = "NetValue Terraform"
  end_date            = timeadd(time_static.signin.rfc3339, "8760h")
  rotate_when_changed = { version = var.signin_secret_version }
  lifecycle { create_before_destroy = true }
}
variable "signin_secret_version" {
  type        = string
  default     = "1"
  description = "Increment before the managed sign-in secret expires; apply foundation then application infrastructure."
}
output "signin_client_id" { value = azuread_application_registration.signin.client_id }
output "signin_client_secret" {
  value     = azuread_application_password.signin.value
  sensitive = true
}
output "deployment_client_id" { value = azuread_application_registration.deployment.client_id }
output "deployment_principal_id" { value = azuread_service_principal.deployment.object_id }
output "resource_group_name" { value = azurerm_resource_group.app.name }
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
resource "time_static" "signin" {
  triggers = { version = var.signin_secret_version }
}
resource "azuread_application_api_access" "signin_graph" {
  application_id = azuread_application_registration.signin.id
  api_client_id  = "00000003-0000-0000-c000-000000000000"
  scope_ids      = ["e1fe6dd8-ba31-4d61-89e7-88639da4683d"] # Existing delegated User.Read permission.
}


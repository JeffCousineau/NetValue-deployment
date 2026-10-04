terraform {
  required_version = ">= 1.10, < 2.0"
  backend "azurerm" {}
  required_providers {
    mssql   = { source = "muecahit94/mssql", version = "= 1.5.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.0" }
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}
provider "azuread" { tenant_id = "e099407c-b3b3-45aa-868e-cc901f513dc5" }
provider "azurerm" {
  features {}
  subscription_id                 = "0bc9dd71-16c4-428e-8160-8a90c7c892f5"
  resource_provider_registrations = "none"
}
provider "mssql" {
  hostname = "netvalue-0620db8f-sql.database.windows.net"
  azure_auth {}
}
data "azurerm_linux_web_app" "app" {
  name                = "netvalue-0620db8f"
  resource_group_name = "rg-netvalue-free"
}
data "azuread_service_principal" "app" { object_id = data.azurerm_linux_web_app.app.identity[0].principal_id }
locals {
  users = {
    app        = { name = "NetValue app", client_id = data.azuread_service_principal.app.client_id }
    deployment = { name = "NetValue deployment", client_id = data.terraform_remote_state.foundation.outputs.deployment_client_id }
  }
  memberships = {
    app_reader        = { user = "app", role = "db_datareader" }
    app_writer        = { user = "app", role = "db_datawriter" }
    deployment_reader = { user = "deployment", role = "db_datareader" }
    deployment_writer = { user = "deployment", role = "db_datawriter" }
    deployment_schema = { user = "deployment", role = "db_ddladmin" }
  }
}
resource "mssql_azuread_service_principal" "user" {
  for_each       = local.users
  database_name  = "NetValue"
  name           = each.value.name
  client_id      = each.value.client_id
  default_schema = "dbo"
  lifecycle { prevent_destroy = true }
}
resource "mssql_database_role_member" "role" {
  for_each      = local.memberships
  database_name = "NetValue"
  role_name     = each.value.role
  member_name   = mssql_azuread_service_principal.user[each.value.user].name
}
data "terraform_remote_state" "foundation" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-netvalue-state"
    storage_account_name = "nvstate0620db8f"
    container_name       = "tfstate"
    key                  = "netvalue.foundation.tfstate"
    use_azuread_auth     = true
  }
}
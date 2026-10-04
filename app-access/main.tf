terraform {
  required_version = ">= 1.10, < 2.0"
  backend "azurerm" {}
  required_providers { azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" } }
}
provider "azurerm" {
  features {}
  subscription_id                 = "0bc9dd71-16c4-428e-8160-8a90c7c892f5"
  resource_provider_registrations = "none"
}
data "azurerm_linux_web_app" "app" {
  name                = "netvalue-0620db8f"
  resource_group_name = "rg-netvalue-free"
}
data "azurerm_mssql_server" "sql" {
  name                = "netvalue-0620db8f-sql"
  resource_group_name = "rg-netvalue-free"
}
resource "azurerm_mssql_firewall_rule" "app" {
  for_each         = { for index, ip in split(",", data.azurerm_linux_web_app.app.possible_outbound_ip_addresses) : tostring(index) => ip }
  name             = "netvalue-app-${each.key}"
  server_id        = data.azurerm_mssql_server.sql.id
  start_ip_address = each.value
  end_ip_address   = each.value
}
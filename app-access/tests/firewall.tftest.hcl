mock_provider "azurerm" {
  mock_data "azurerm_linux_web_app" {
    defaults = {
      outbound_ip_addresses = "20.200.112.226"
      possible_outbound_ip_addresses = "20.200.112.226,52.228.101.67"
    }
  }
  mock_data "azurerm_mssql_server" {
    defaults = { id = "/subscriptions/0bc9dd71-16c4-428e-8160-8a90c7c892f5/resourceGroups/rg-netvalue-free/providers/Microsoft.Sql/servers/netvalue-0620db8f-sql" }
  }
}
run "covers_shared_worker_possible_ips" {
  command = plan
  assert {
    condition = length(azurerm_mssql_firewall_rule.app) == 2 && azurerm_mssql_firewall_rule.app["1"].start_ip_address == "52.228.101.67"
    error_message = "SQL access must cover possible worker IPs beyond the current outbound IP list."
  }
  assert {
    condition = alltrue([for rule in azurerm_mssql_firewall_rule.app : rule.start_ip_address == rule.end_ip_address && rule.start_ip_address != "0.0.0.0"])
    error_message = "Every rule must allow one exact address; no broad Azure firewall bypass."
  }
}

output "resource_group_name" { value = data.azurerm_resource_group.netvalue.name }
output "web_app_name" { value = azurerm_linux_web_app.netvalue.name }
output "web_app_url" { value = "https://${azurerm_linux_web_app.netvalue.default_hostname}" }
output "web_app_principal_id" { value = azurerm_linux_web_app.netvalue.identity[0].principal_id }
output "web_app_outbound_ips" { value = azurerm_linux_web_app.netvalue.outbound_ip_addresses }
output "sql_server_name" { value = azurerm_mssql_server.netvalue.name }
output "sql_host" { value = azurerm_mssql_server.netvalue.fully_qualified_domain_name }

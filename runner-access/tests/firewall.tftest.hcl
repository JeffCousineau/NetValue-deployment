mock_provider "azurerm" {}
run "rejects_broad_azure_bypass" {
  command = plan
  variables { runner_ip = "0.0.0.0" }
  expect_failures = [var.runner_ip]
}
run "rejects_address_ranges" {
  command = plan
  variables { runner_ip = "1.2.3.4/24" }
  expect_failures = [var.runner_ip]
}
run "allows_only_runner_address" {
  command = plan
  variables { runner_ip = "20.200.112.226" }
  assert {
    condition = azurerm_mssql_firewall_rule.runner.start_ip_address == azurerm_mssql_firewall_rule.runner.end_ip_address
    error_message = "Temporary access must never include a range."
  }
}

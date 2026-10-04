mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      name     = "rg-netvalue-free"
      location = "canadacentral"
      id       = "/subscriptions/0bc9dd71-16c4-428e-8160-8a90c7c892f5/resourceGroups/rg-netvalue-free"
    }
  }
}
mock_provider "azapi" {}
run "requires_free_offer_verification" {
  command = plan
  variables { free_offer_verified = false }
  expect_failures = [azurerm_service_plan.free]
}
run "uses_reviewed_cost_limits" {
  command = plan
  variables { free_offer_verified = true }
  assert {
    condition     = azurerm_service_plan.free.sku_name == "F1" && azurerm_service_plan.free.os_type == "Linux"
    error_message = "App Service must remain on Linux F1."
  }
  assert {
    condition     = azurerm_linux_web_app.netvalue.site_config[0].always_on == false
    error_message = "Always On is not available on F1."
  }
  assert {
    condition     = azapi_resource.database.body.properties.useFreeLimit && azapi_resource.database.body.properties.freeLimitExhaustionBehavior == "AutoPause"
    error_message = "SQL must stop at its free limit instead of billing overages."
  }
  assert {
    condition     = azapi_resource.database.body.properties.maxSizeBytes <= 34359738368 && azapi_resource.database.body.properties.requestedBackupStorageRedundancy == "Local"
    error_message = "SQL data and backup storage must stay within the reviewed offer."
  }
}

data "azurerm_resource_group" "netvalue" {
  name = "rg-netvalue-free"
}
resource "azurerm_service_plan" "free" {
  name                = "${local.name}-plan"
  resource_group_name = data.azurerm_resource_group.netvalue.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "F1"
  tags                = local.tags
  lifecycle {
    precondition {
      condition     = var.free_offer_verified
      error_message = "Verify free offer eligibility and F1 availability first. No paid fallback."
    }
  }
}
resource "azurerm_linux_web_app" "netvalue" {
  name                = local.name
  resource_group_name = data.azurerm_resource_group.netvalue.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.free.id
  https_only          = true
  identity { type = "SystemAssigned" }
  site_config {
    always_on               = false
    websockets_enabled      = true
    ftps_state              = "Disabled"
    minimum_tls_version     = "1.2"
    scm_minimum_tls_version = "1.2"
    app_command_line        = "dotnet /home/site/wwwroot/NetValue.dll"
    application_stack { dotnet_version = "10.0" }
  }
  app_settings = {
    ASPNETCORE_ENVIRONMENT              = "Production"
    Database__Provider                  = "SqlServer"
    Database__DataDirectory             = "/home/netvalue-data"
    ASPNETCORE_FORWARDEDHEADERS_ENABLED = "true"
    WEBSITE_RUN_FROM_PACKAGE            = "1"
    Authentication__TenantId            = var.tenant_id
    Authentication__ClientId            = "209f8009-5376-440d-8d26-f7316be55321"
    Households__BootstrapOwnerObjectId  = var.owner_object_id
    AllowedHosts                        = "${local.name}.azurewebsites.net"
    ConnectionStrings__NetValue         = "Server=tcp:${local.sql_name}.database.windows.net,1433;Database=NetValue;Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;Pooling=False;"
  }
  tags = local.tags
  # GitHub sets the client secret after provisioning. Never pass it as a TF variable.
  # Azure provider refresh can still include app settings in private remote state.
  lifecycle { ignore_changes = [app_settings] }
}
resource "azurerm_mssql_server" "netvalue" {
  name                = local.sql_name
  resource_group_name = data.azurerm_resource_group.netvalue.name
  location            = var.location
  version             = "12.0"
  minimum_tls_version = "1.2"
  azuread_administrator {
    login_username              = "NetValue owner"
    object_id                   = var.owner_object_id
    tenant_id                   = var.tenant_id
    azuread_authentication_only = true
  }
  tags = local.tags
  lifecycle { prevent_destroy = true }
}
# AzAPI exposes the free-offer properties explicitly; a generic SQL SKU is not free.
resource "azapi_resource" "database" {
  type      = "Microsoft.Sql/servers/databases@2023-08-01"
  name      = "NetValue"
  parent_id = azurerm_mssql_server.netvalue.id
  location  = var.location
  body = {
    sku = { name = "GP_S_Gen5_2", tier = "GeneralPurpose", family = "Gen5", capacity = 2 }
    properties = {
      useFreeLimit                     = true
      freeLimitExhaustionBehavior      = "AutoPause"
      autoPauseDelay                   = 60
      minCapacity                      = 0.5
      maxSizeBytes                     = 34359738368
      requestedBackupStorageRedundancy = "Local"
      zoneRedundant                    = false
    }
  }
  lifecycle { prevent_destroy = true }
}

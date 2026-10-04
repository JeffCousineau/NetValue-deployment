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
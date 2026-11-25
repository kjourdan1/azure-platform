data "terraform_remote_state" "landing_zone" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-azpl-tfstate-prd-frc-001"
    storage_account_name = "stazpltfstateprdfrc002"
    container_name       = "tfstate"
    key                  = "landing-zone.tfstate"
    use_azuread_auth     = true
  }
}

# Subscription azpl-lz-sylo (management group online), retrouvée par la landing zone.
provider "azurerm" {
  features {}
  storage_use_azuread = true
  subscription_id     = data.terraform_remote_state.landing_zone.outputs.subscription_ids.lz_sylo
}

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

# Socle réseau, Key Vault, ACR et identités de la landing zone Sylo.
data "terraform_remote_state" "lz_sylo" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-azpl-tfstate-prd-frc-001"
    storage_account_name = "stazpltfstateprdfrc002"
    container_name       = "tfstate"
    key                  = "lz-sylo.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
  subscription_id     = data.terraform_remote_state.landing_zone.outputs.subscription_ids.lz_sylo
}

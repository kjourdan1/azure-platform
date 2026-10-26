data "terraform_remote_state" "landing_zone" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-azpl-tfstate-prd-frc-001"
    storage_account_name = "stazpltfstateprdfrc001"
    container_name       = "tfstate"
    key                  = "landing-zone.tfstate"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "lz_aks" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-azpl-tfstate-prd-frc-001"
    storage_account_name = "stazpltfstateprdfrc001"
    container_name       = "tfstate"
    key                  = "lz-aks.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id = data.terraform_remote_state.landing_zone.outputs.subscription_ids.lz_aks
}

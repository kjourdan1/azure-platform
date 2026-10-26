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

data "terraform_remote_state" "platform" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-azpl-tfstate-prd-frc-001"
    storage_account_name = "stazpltfstateprdfrc001"
    container_name       = "tfstate"
    key                  = "platform.tfstate"
    use_azuread_auth     = true
  }
}

# Multi-subscription explicite : le spoke dans azpl-lz-aks, le côté hub du peering dans
# azpl-platform. IDs lus dans le state de la landing zone.
provider "azurerm" {
  features {}
  subscription_id = data.terraform_remote_state.landing_zone.outputs.subscription_ids.lz_aks
}

provider "azurerm" {
  alias = "platform"
  features {}
  subscription_id = data.terraform_remote_state.landing_zone.outputs.subscription_ids.platform
}

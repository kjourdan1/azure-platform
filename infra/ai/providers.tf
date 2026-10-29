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

# Même subscription que le cluster : la couche IA sert d'abord ses applications. Une
# subscription IA dédiée (vending) est la cible, écartée pour l'instant : elle repartirait
# sans quota de modèles.
provider "azurerm" {
  features {}
  subscription_id = data.terraform_remote_state.landing_zone.outputs.subscription_ids.lz_aks
}

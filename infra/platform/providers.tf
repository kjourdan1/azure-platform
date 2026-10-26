# Subscription lue dans le state de la landing zone (subscription vending) : aucun ID
# dans le code. Les resource providers ont été enregistrés à la vente.
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

provider "azurerm" {
  features {}
  subscription_id = data.terraform_remote_state.landing_zone.outputs.subscription_ids.platform
}

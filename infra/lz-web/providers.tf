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

# Landing zone online du portfolio : la CI y est Owner (subscription créée par alias), alors
# qu'elle n'a aucun droit d'écriture sur LAB.
provider "azurerm" {
  features {}
  subscription_id = data.terraform_remote_state.landing_zone.outputs.subscription_ids.lz_web
}

# Même compte de state que le bootstrap, une clé par couche.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-azpl-tfstate-prd-frc-001"
    storage_account_name = "stazpltfstateprdfrc001"
    container_name       = "tfstate"
    key                  = "landing-zone.tfstate"
    use_azuread_auth     = true
  }
}

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-azpl-tfstate-prd-frc-001"
    storage_account_name = "stazpltfstateprdfrc002"
    container_name       = "tfstate"
    key                  = "ai.tfstate"
    use_azuread_auth     = true
  }
}

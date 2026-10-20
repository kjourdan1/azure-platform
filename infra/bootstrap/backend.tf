# Ajouté après le premier apply : le state du bootstrap vit dans le compte qu'il a créé.
# Pas de clé d'accès : authentification Entra ID uniquement.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-azpl-tfstate-prd-frc-001"
    storage_account_name = "stazpltfstateprdfrc001"
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
  }
}

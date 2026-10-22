terraform {
  # Aligné sur la contrainte de Azure/avm-ptn-alz (>= 1.12) utilisé par la Landing Zone.
  required_version = ">= 1.12, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }

  # Pas de bloc backend au premier apply : le state est local le temps de créer
  # le Storage Account qui l'hébergera. Voir README.md, étape « migration du state ».
}

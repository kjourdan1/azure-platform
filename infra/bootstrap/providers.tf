# La subscription cible n'est jamais écrite dans le code : elle est lue depuis
# ARM_SUBSCRIPTION_ID (poste local) ou injectée par la CI.
provider "azurerm" {
  features {}

  # Le Storage Account n'a pas de clé d'accès : tout appel data plane passe par Entra ID.
  storage_use_azuread = true

  # azurerm 5.x n'enregistre plus aucun resource provider par défaut.
  # On déclare explicitement ceux dont le bootstrap a besoin.
  resource_providers_to_register = [
    "Microsoft.Storage",
    "Microsoft.ManagedIdentity",
    "Microsoft.Consumption",
  ]
}

# Ressources de facturation (budget global, rôle de facturation) : hors de azurerm.
provider "azapi" {}

# Jeton lu depuis GITHUB_TOKEN (export GITHUB_TOKEN=$(gh auth token)) : jamais stocké.
# manage_github = false : pas d'owner, donc aucun appel API à l'initialisation du provider.
provider "github" {
  owner = var.manage_github ? var.github_owner : null
}

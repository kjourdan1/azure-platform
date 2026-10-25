data "azurerm_subscription" "lz_aks" {}

locals {
  # Même forme que les identités du bootstrap : IDs immuables du propriétaire et du dépôt.
  github_subject_base = "repo:kjourdan1@97712877/azure-platform@1325008901"
}

# Identité de lab-down : supprime le cluster chaque soir sans approbation humaine. Elle
# n'a donc que ce droit-là, et n'est approuvée que pour l'environnement GitHub lab.
resource "azurerm_user_assigned_identity" "lab" {
  name                = "id-${local.project}-lab-${local.suffix}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "lab" {
  name                      = "github-environment-lab"
  user_assigned_identity_id = azurerm_user_assigned_identity.lab.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "${local.github_subject_base}:environment:lab"
}

# Aucun rôle intégré ne se limite à supprimer un cluster (AKS Contributor peut aussi le
# créer et le modifier). Pas de suppression de resource group : le réseau, le coffre et
# le registre sont hors de portée par construction, sans verrou à maintenir.
resource "azurerm_role_definition" "lab_teardown" {
  name        = "${local.project}-lab-teardown"
  scope       = data.azurerm_subscription.lz_aks.id
  description = "Lecture et suppression des clusters AKS (lab-down)."

  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/delete",
      # Suivi de l'opération asynchrone de suppression par az aks delete.
      "Microsoft.ContainerService/locations/operations/read",
      "Microsoft.ContainerService/locations/operationresults/read",
    ]
  }

  assignable_scopes = [data.azurerm_subscription.lz_aks.id]
}

resource "azurerm_role_assignment" "lab_teardown" {
  scope              = data.azurerm_subscription.lz_aks.id
  role_definition_id = azurerm_role_definition.lab_teardown.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.lab.principal_id
  principal_type     = "ServicePrincipal"
}

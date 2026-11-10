# Identité du workflow build-images : pousser les images des applications dans le
# registre, rien d'autre. Fédérée à la branche main uniquement : une PR construit et
# scanne ses images sans jamais pouvoir les publier.
resource "azurerm_user_assigned_identity" "build" {
  name                = "id-${local.project}-build-${local.suffix}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "build" {
  name                      = "github-branch-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.build.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "${local.github_subject_base}:ref:refs/heads/main"
}

# AcrPush : push et pull des images. Pas de build côté registre (ACR Tasks), qui
# demanderait un rôle de gestion : l'image est construite sur le runner.
resource "azurerm_role_assignment" "build_push" {
  scope                = azurerm_container_registry.aks.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.build.principal_id
  principal_type       = "ServicePrincipal"
}

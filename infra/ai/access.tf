data "azurerm_subscription" "current" {}

# L'opérateur utilise le projet (portail Foundry, playground, agents) sans droit de gestion
# sur le compte : la configuration passe par Terraform. Rôle « Foundry User » référencé par
# son ID : Microsoft l'a renommé (anciennement « Azure AI User »), l'ID ne change pas.
resource "azurerm_role_assignment" "operator_foundry_user" {
  scope              = azurerm_cognitive_account.foundry.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = var.operator_object_id
}

# Identité du workflow ai-smoke : appeler le modèle, rien d'autre. Fédérée à l'environnement
# GitHub lab (déclenchement manuel, sans approbation) : son seul pouvoir est de consommer
# quelques tokens, plafonnés par la capacité du déploiement.
locals {
  github_subject_base = "repo:kjourdan1@97712877/azure-platform@1325008901"
}

resource "azurerm_user_assigned_identity" "smoke" {
  name                = "id-${local.project}-ai-smoke-${local.suffix}"
  resource_group_name = azurerm_resource_group.ai.name
  location            = azurerm_resource_group.ai.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "smoke" {
  name                      = "github-environment-lab"
  user_assigned_identity_id = azurerm_user_assigned_identity.smoke.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "${local.github_subject_base}:environment:lab"
}

resource "azurerm_role_assignment" "smoke_inference" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.smoke.principal_id
  principal_type       = "ServicePrincipal"
}

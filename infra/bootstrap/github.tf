data "github_user" "approver" {
  count    = var.manage_github ? 1 : 0
  username = var.github_owner
}

# L'environnement protégé : seul un job qui le déclare obtient un jeton
# dont le sub correspond à l'identité apply. L'approbation est le vrai verrou.
resource "github_repository_environment" "prd" {
  count = var.manage_github ? 1 : 0

  repository          = var.github_repository
  environment         = var.github_environment
  can_admins_bypass   = false
  prevent_self_review = false # unique mainteneur : je dois pouvoir approuver mes runs

  reviewers {
    users = [data.github_user.approver[0].id]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "prd_main" {
  count = var.manage_github ? 1 : 0

  repository     = var.github_repository
  environment    = github_repository_environment.prd[0].environment
  branch_pattern = "main"
}

# Identifiants non secrets mais stockés en secrets Actions : GitHub les masque dans
# toutes les lignes de log d'un dépôt public.
resource "github_actions_secret" "repo" {
  for_each = var.manage_github ? {
    AZURE_TENANT_ID       = data.azurerm_subscription.current.tenant_id
    AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
    AZURE_CLIENT_ID_PLAN  = azurerm_user_assigned_identity.ci["plan"].client_id
    OPERATOR_OBJECT_ID    = var.operator_object_id
  } : {}

  repository  = var.github_repository
  secret_name = each.key
  value       = each.value
}

# Le client ID d'apply n'est exposé qu'aux jobs de l'environnement prd.
resource "github_actions_environment_secret" "apply_client_id" {
  count = var.manage_github ? 1 : 0

  repository  = var.github_repository
  environment = github_repository_environment.prd[0].environment
  secret_name = "AZURE_CLIENT_ID_APPLY"
  value       = azurerm_user_assigned_identity.ci["apply"].client_id
}

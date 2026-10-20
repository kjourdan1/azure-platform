data "github_user" "approver" {
  username = var.github_owner
}

# L'environnement protégé : seul un job qui le déclare obtient un jeton
# dont le sub correspond à l'identité apply. L'approbation est le vrai verrou.
resource "github_repository_environment" "prd" {
  repository          = var.github_repository
  environment         = var.github_environment
  can_admins_bypass   = false
  prevent_self_review = false # unique mainteneur : je dois pouvoir approuver mes runs

  reviewers {
    users = [data.github_user.approver.id]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "prd_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.prd.environment
  branch_pattern = "main"
}

# Valeurs non secrètes mais hors du code : variables Actions, pas secrets.
resource "github_actions_variable" "repo" {
  for_each = {
    AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
    AZURE_CLIENT_ID_PLAN  = azurerm_user_assigned_identity.ci["plan"].client_id
    TFSTATE_RG            = azurerm_resource_group.tfstate.name
    TFSTATE_ACCOUNT       = azurerm_storage_account.tfstate.name
    TFSTATE_CONTAINER     = azurerm_storage_container.tfstate.name
  }

  repository    = var.github_repository
  variable_name = each.key
  value         = each.value
}

# Le client ID d'apply n'est exposé qu'aux jobs de l'environnement prd.
resource "github_actions_environment_variable" "apply_client_id" {
  repository    = var.github_repository
  environment   = github_repository_environment.prd.environment
  variable_name = "AZURE_CLIENT_ID_APPLY"
  value         = azurerm_user_assigned_identity.ci["apply"].client_id
}

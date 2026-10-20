locals {
  github_oidc_issuer   = "https://token.actions.githubusercontent.com"
  github_oidc_audience = ["api://AzureADTokenExchange"]
  github_subject_base  = "repo:${var.github_owner}/${var.github_repository}"

  # Une identité = un sujet exact. Aucun joker : seul un job dans ce contexte précis
  # obtient un jeton Azure pour cette identité.
  ci_identities = {
    plan = {
      subject = "${local.github_subject_base}:pull_request"
      # Lecture seule sur Azure : plan exécute le code de la PR.
      root_roles = ["Reader"]
    }
    apply = {
      subject = "${local.github_subject_base}:environment:${var.github_environment}"
      root_roles = [
        "Management Group Contributor",
        "Resource Policy Contributor",
        "User Access Administrator",
      ]
    }
  }

  # Produit cartésien identité × rôle racine, indexé pour for_each.
  root_role_assignments = merge([
    for identity, cfg in local.ci_identities : {
      for role in cfg.root_roles : "${identity}-${role}" => {
        identity = identity
        role     = role
      }
    }
  ]...)
}

# Tenant Root Group : son nom est l'ID du tenant.
data "azurerm_management_group" "root" {
  name = data.azurerm_client_config.current.tenant_id
}

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "identity" {
  name     = local.names.resource_group_identity
  location = var.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "ci" {
  for_each = local.ci_identities

  name                = "id-${local.project}-${each.key}-${var.environment}-${local.region_code}-001"
  resource_group_name = azurerm_resource_group.identity.name
  location            = azurerm_resource_group.identity.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "ci" {
  for_each = local.ci_identities

  name                      = "github-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci[each.key].id
  issuer                    = local.github_oidc_issuer
  audience                  = local.github_oidc_audience
  subject                   = each.value.subject
}

resource "azurerm_role_assignment" "ci_root" {
  for_each = local.root_role_assignments

  scope                = data.azurerm_management_group.root.id
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.ci[each.value.identity].principal_id
  principal_type       = "ServicePrincipal"
}

# apply déploie aussi des ressources (Log Analytics, hub réseau) dans la subscription.
# Contributor limité à la subscription, pas à la racine.
resource "azurerm_role_assignment" "apply_subscription" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ci["apply"].principal_id
  principal_type       = "ServicePrincipal"
}

# plan pose un lease (verrou) sur le blob du state : c'est une écriture data plane.
resource "azurerm_role_assignment" "ci_state" {
  for_each = local.ci_identities

  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ci[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

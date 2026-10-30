locals {
  github_oidc_issuer   = "https://token.actions.githubusercontent.com"
  github_oidc_audience = ["api://AzureADTokenExchange"]
  # GitHub inclut les IDs immuables du propriétaire et du dépôt dans le sub :
  # un dépôt recréé sous le même nom après un renommage n'obtient pas le même sujet.
  github_subject_base = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}"

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
  name = data.azurerm_subscription.current.tenant_id
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

# apply n'a pas de rôle déclaré sur les subscriptions qu'elle déploie : elle en est Owner
# parce qu'elle les a créées par alias (landing-zone). Un Contributor ajouté ici serait
# redondant ; il n'a d'ailleurs jamais été appliqué (reprise brownfield, revue des droits).

# Rafraîchir un cluster AKS appelle listClusterUserCredential, que Reader n'inclut pas :
# sans ce rôle, le plan de infra/aks échoue dès que le cluster tourne. Il ne donne qu'un
# kubeconfig sans secret (comptes locaux désactivés, accès à l'API par Entra + Azure RBAC),
# donc aucun accès aux objets du cluster.
resource "azurerm_role_assignment" "plan_aks_user" {
  for_each = toset(var.platform_subscription_ids)

  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azurerm_user_assigned_identity.ci["plan"].principal_id
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

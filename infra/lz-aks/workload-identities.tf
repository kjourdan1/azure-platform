# Identités des charges du cluster qui parlent à Azure. Permanentes, avec leurs rôles :
# seuls les credentials fédérés suivent le cluster (infra/aks), car l'émetteur OIDC change
# à chaque création.
locals {
  workload_identities = toset([
    "external_secrets",
    "external_dns",
    # ai-gateway : une identité par microservice, chacune limitée à son besoin.
    "ai_chat", # appel du modèle : rôle posé sur le compte Foundry par infra/ai
    "ai_cost", # lecture des coûts et de l'inventaire de toute la plateforme
  ])

  # Clés existantes conservées (external_secrets, external_dns) : aucune réattribution.
  workload_roles = {
    # Secrets Officer et non Secrets User : ESO crée les mots de passe absents du coffre
    # (générateur + PushSecret), puis les relit. Les secrets restent hors du state
    # Terraform, au prix d'un droit d'écriture sur ce coffre dédié au cluster.
    external_secrets = {
      identity = "external_secrets"
      role     = "Key Vault Secrets Officer"
      scope    = azurerm_key_vault.aks.id
    }
    # Écriture limitée à la sous-zone du lab, jamais au reste du domaine.
    external_dns = {
      identity = "external_dns"
      role     = "DNS Zone Contributor"
      scope    = azurerm_dns_zone.lab.id
    }
    # Coût facturé des 4 subscriptions, hérité depuis la racine de la hiérarchie ALZ.
    ai_cost_billing = {
      identity = "ai_cost"
      role     = "Cost Management Reader"
      scope    = local.alz_root_management_group_id
    }
    # Inventaire des ressources facturables (Resource Graph) pour le coût en direct.
    ai_cost_inventory = {
      identity = "ai_cost"
      role     = "Reader"
      scope    = local.alz_root_management_group_id
    }
  }

  alz_root_management_group_id = "/providers/Microsoft.Management/managementGroups/alz"
}

resource "azurerm_user_assigned_identity" "workload" {
  for_each = local.workload_identities

  name                = "id-${local.project}-${replace(each.key, "_", "-")}-${local.suffix}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "workload" {
  for_each = local.workload_roles

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.workload[each.value.identity].principal_id
  principal_type       = "ServicePrincipal"
}

# Identités des contrôleurs du cluster qui parlent à Azure. Permanentes, avec leurs rôles :
# seuls les credentials fédérés suivent le cluster (infra/aks), car l'émetteur OIDC change
# à chaque création.
locals {
  workload_identities = {
    # Secrets Officer et non Secrets User : ESO crée les mots de passe absents du coffre
    # (générateur + PushSecret), puis les relit. Les secrets restent hors du state
    # Terraform, au prix d'un droit d'écriture sur ce coffre dédié au cluster.
    external_secrets = {
      role  = "Key Vault Secrets Officer"
      scope = azurerm_key_vault.aks.id
    }
    # Écriture limitée à la sous-zone du lab, jamais au reste du domaine.
    external_dns = {
      role  = "DNS Zone Contributor"
      scope = azurerm_dns_zone.lab.id
    }
  }
}

resource "azurerm_user_assigned_identity" "workload" {
  for_each = local.workload_identities

  name                = "id-${local.project}-${replace(each.key, "_", "-")}-${local.suffix}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "workload" {
  for_each = local.workload_identities

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.workload[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

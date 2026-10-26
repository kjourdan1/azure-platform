data "azurerm_client_config" "current" {}

# Coffre du chemin des secrets : Key Vault → Workload Identity → External Secrets → pod.
# Conforme aux deny de la landing zone (Enforce-GR-KeyVault) : RBAC obligatoire, soft
# delete et purge protection. Ressource permanente : la purge protection réserverait le
# nom pendant la rétention si on la détruisait chaque soir.
resource "azurerm_key_vault" "aks" {
  #checkov:skip=CKV_AZURE_189:Endpoint public tant que les runners sont hébergés ; accès Entra RBAC uniquement
  #checkov:skip=CKV_AZURE_109:Même raison : pare-feu à réactiver avec un runner self-hosted à IP fixe
  #checkov:skip=CKV2_AZURE_32:Private endpoint payant et inatteignable depuis les runners hébergés
  name                       = "kv-${local.project}-aks-${local.suffix}"
  resource_group_name        = azurerm_resource_group.shared.name
  location                   = azurerm_resource_group.shared.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "sylo" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}

# --- Réseau : spoke privé. Aucune ressource à coût fixe (NAT Gateway, Firewall, App Gateway
# sont interdits par les policies FinOps). Appairage au hub : à ajouter avec la stack platform.

resource "azurerm_virtual_network" "sylo" {
  name                = local.names.vnet
  resource_group_name = azurerm_resource_group.sylo.name
  location            = azurerm_resource_group.sylo.location
  address_space       = [var.address_space]
  tags                = local.tags
}

# Environnement Container Apps (profil de charge Consumption) : /27 minimum, délégué.
resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = azurerm_resource_group.sylo.name
  virtual_network_name = azurerm_virtual_network.sylo.name
  address_prefixes     = [cidrsubnet(var.address_space, 3, 0)]

  delegation {
    name = "aca"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# PostgreSQL Flexible Server en accès privé : sous-réseau délégué dédié.
resource "azurerm_subnet" "pg" {
  name                 = "snet-pg"
  resource_group_name  = azurerm_resource_group.sylo.name
  virtual_network_name = azurerm_virtual_network.sylo.name
  address_prefixes     = [cidrsubnet(var.address_space, 4, 2)]

  delegation {
    name = "pg"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# NSG sans règle personnalisée : les règles par défaut laissent passer le trafic du VNet et
# la sortie Internet. Il rend le contrôle explicite et prêt à durcir.
resource "azurerm_network_security_group" "sylo" {
  name                = "nsg-${local.project}-sylo-${local.suffix}"
  resource_group_name = azurerm_resource_group.sylo.name
  location            = azurerm_resource_group.sylo.location
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "aca" {
  subnet_id                 = azurerm_subnet.aca.id
  network_security_group_id = azurerm_network_security_group.sylo.id
}

resource "azurerm_subnet_network_security_group_association" "pg" {
  subnet_id                 = azurerm_subnet.pg.id
  network_security_group_id = azurerm_network_security_group.sylo.id
}

resource "azurerm_private_dns_zone" "pg" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.sylo.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "pg" {
  name                = "link-${local.names.vnet}"
  private_dns_zone_id = azurerm_private_dns_zone.pg.id
  virtual_network_id  = azurerm_virtual_network.sylo.id
  tags                = local.tags
}

# --- Observabilité : workspace propre à Sylo tant que le Log Analytics central (stack platform)
# n'existe pas dans ce tenant. Rétention minimale pour tenir le budget.

resource "azurerm_log_analytics_workspace" "sylo" {
  name                = local.names.law
  resource_group_name = azurerm_resource_group.sylo.name
  location            = azurerm_resource_group.sylo.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.5
  tags                = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# --- Secrets : Key Vault en RBAC, aucune politique d'accès.

resource "azurerm_key_vault" "sylo" {
  #checkov:skip=CKV_AZURE_189:Accès public conservé : les runners GitHub hébergés n'ont pas d'IP fixe ; l'authentification est Entra uniquement.
  #checkov:skip=CKV2_AZURE_32:Pas de private endpoint au MVP : coût fixe évité (ADR-010).
  #checkov:skip=CKV_AZURE_109:Pare-feu réseau reporté avec le runner self-hosted.
  #checkov:skip=CKV_AZURE_110:Purge protection désactivée au MVP : un coffre supprimé doit pouvoir être recréé sans délai de 90 jours.
  #checkov:skip=CKV_AZURE_42:Même raison : la suppression récupérable 7 jours reste active (soft delete).
  name                       = local.names.key_vault
  resource_group_name        = azurerm_resource_group.sylo.name
  location                   = azurerm_resource_group.sylo.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# --- Images : ACR Basic propre à la landing zone, sans compte admin.

resource "azurerm_container_registry" "sylo" {
  #checkov:skip=CKV_AZURE_163:Scan de vulnérabilités : Defender non facturé sur cette subscription.
  #checkov:skip=CKV_AZURE_165:Géo-réplication : SKU Basic, coût évité.
  #checkov:skip=CKV_AZURE_164:Images non signées au MVP.
  #checkov:skip=CKV_AZURE_167:Rétention des manifests non taguées : SKU Basic.
  #checkov:skip=CKV_AZURE_233:Zone redundancy : SKU Basic.
  #checkov:skip=CKV_AZURE_237:Dedicated data endpoint : SKU Basic.
  #checkov:skip=CKV_AZURE_139:Accès public conservé pour la CI applicative Azure DevOps.
  #checkov:skip=CKV_AZURE_166:Quarantaine des images : fonctionnalité du SKU Premium.
  name                = local.names.registry
  resource_group_name = azurerm_resource_group.sylo.name
  location            = azurerm_resource_group.sylo.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# --- Identités managées : une par charge (api, web, n8n).

resource "azurerm_user_assigned_identity" "workload" {
  for_each = local.workloads

  name                = "id-${local.project}-sylo-${each.key}-${local.suffix}"
  resource_group_name = azurerm_resource_group.sylo.name
  location            = azurerm_resource_group.sylo.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  for_each = local.workloads

  scope                = azurerm_container_registry.sylo.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.workload[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# Secrets en lecture seule : api (webhook Teams, futures clés Qonto) et n8n (mot de passe de sa base).
resource "azurerm_role_assignment" "kv_secrets_user" {
  for_each = toset(["api", "n8n"])

  scope                = azurerm_key_vault.sylo.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

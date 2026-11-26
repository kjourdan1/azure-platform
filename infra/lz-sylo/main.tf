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

  # La landing zone refuse un sous-réseau créé sans NSG : il est donc attaché dès la création.
  network_security_group_id_wo         = azurerm_network_security_group.sylo.id
  network_security_group_id_wo_version = 1

  delegation {
    name = "aca"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# PostgreSQL Flexible Server en northeurope : Burstable B1ms est refusé (SkuNotAvailable) en
# France Central pour cette subscription et accepté en northeurope (test du 2026-11-25). Un serveur
# intégré à un VNet doit être dans la région de ce VNet : VNet dédié, appairé au VNet France Central.
resource "azurerm_virtual_network" "pg" {
  name                = "vnet-${local.project}-sylo-${local.pg_suffix}"
  resource_group_name = azurerm_resource_group.sylo.name
  location            = var.pg_location
  address_space       = [var.pg_address_space]
  tags                = local.tags
}

resource "azurerm_network_security_group" "pg" {
  name                = "nsg-${local.project}-sylo-${local.pg_suffix}"
  resource_group_name = azurerm_resource_group.sylo.name
  location            = var.pg_location
  tags                = local.tags
}

# Sous-réseau délégué au serveur PostgreSQL, NSG attaché dès la création (policy de la landing zone).
resource "azurerm_subnet" "pg" {
  name                 = "snet-pg"
  resource_group_name  = azurerm_resource_group.sylo.name
  virtual_network_name = azurerm_virtual_network.pg.name
  address_prefixes     = [cidrsubnet(var.pg_address_space, 4, 0)]

  network_security_group_id_wo         = azurerm_network_security_group.pg.id
  network_security_group_id_wo_version = 1

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

# La zone DNS privée est liée aux deux VNet : le serveur s'y enregistre depuis northeurope et les
# Container Apps la résolvent depuis France Central.
resource "azurerm_private_dns_zone_virtual_network_link" "pg_neu" {
  name                = "link-vnet-${local.project}-sylo-${local.pg_suffix}"
  private_dns_zone_id = azurerm_private_dns_zone.pg.id
  virtual_network_id  = azurerm_virtual_network.pg.id
  tags                = local.tags
}

# Appairage bidirectionnel France Central <-> northeurope (trafic PostgreSQL des Container Apps).
resource "azurerm_virtual_network_peering" "sylo_to_pg" {
  name                         = "peer-sylo-frc-to-neu"
  resource_group_name          = azurerm_resource_group.sylo.name
  virtual_network_name         = azurerm_virtual_network.sylo.name
  remote_virtual_network_id    = azurerm_virtual_network.pg.id
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "pg_to_sylo" {
  name                         = "peer-sylo-neu-to-frc"
  resource_group_name          = azurerm_resource_group.sylo.name
  virtual_network_name         = azurerm_virtual_network.pg.name
  remote_virtual_network_id    = azurerm_virtual_network.sylo.id
  allow_virtual_network_access = true
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
  name                       = local.names.key_vault
  resource_group_name        = azurerm_resource_group.sylo.name
  location                   = azurerm_resource_group.sylo.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = true # exigé par Enforce-GR-KeyVault ; coffre permanent
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

# --- Construction des images : identité dédiée à la CI du dépôt privé sylo (GitHub Actions),
# fédérée en OIDC (aucun secret), avec le seul droit de pousser dans l'ACR. Elle ne déploie rien :
# la révision déployée est fixée par Terraform (infra/sylo).
resource "azurerm_user_assigned_identity" "build" {
  name                = "id-${local.project}-sylo-build-${local.suffix}"
  resource_group_name = azurerm_resource_group.sylo.name
  location            = azurerm_resource_group.sylo.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "build" {
  name                      = "github-sylo-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.build.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:${var.app_repository}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "build_acr_push" {
  scope                = azurerm_container_registry.sylo.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.build.principal_id
  principal_type       = "ServicePrincipal"
}

data "azurerm_client_config" "current" {}

# --- PostgreSQL Flexible Server : Burstable B1ms, PostgreSQL 16, accès privé (ADR-010).
# Authentification Entra pour l'API et les jobs. L'unique exception est le rôle PostgreSQL
# « n8n » à mot de passe (ADR-027) : son mot de passe est généré hors Terraform, stocké dans le
# Key Vault (n8n-db-password), et il n'a aucun droit sur la base sylo. Le mot de passe du compte
# administrateur, lui, n'est jamais utilisé par une charge.

resource "random_password" "pg_admin" {
  length  = 40
  special = false
}

resource "azurerm_postgresql_flexible_server" "sylo" {
  #checkov:skip=CKV_AZURE_136:Géo-réplication des sauvegardes : coût évité, sauvegardes locales 7 jours (ADR-010).
  #checkov:skip=CKV2_AZURE_57:Accès privé via sous-réseau délégué, pas de private endpoint.
  name                = local.names.postgres
  resource_group_name = local.lz.resource_group.name
  location            = local.lz.resource_group.location
  version             = "16"
  sku_name            = "B_Standard_B1ms"
  storage_mb          = 32768

  backup_retention_days = 7

  delegated_subnet_id           = local.lz.network.pg_subnet_id
  private_dns_zone_id           = local.lz.network.pg_dns_zone_id
  public_network_access_enabled = false

  administrator_login    = "syloadmin"
  administrator_password = random_password.pg_admin.result

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  tags = local.tags

  lifecycle {
    prevent_destroy = true
    # La zone de disponibilité est choisie par Azure à la création.
    ignore_changes = [zone]
  }
}

# L'API et les jobs s'authentifient par jeton Entra : l'identité de l'API administre la base sylo.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "api" {
  server_name         = azurerm_postgresql_flexible_server.sylo.name
  resource_group_name = local.lz.resource_group.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = local.lz.workload_identities.api.principal_id
  principal_name      = "id-${local.project}-sylo-api-${local.suffix}"
  principal_type      = "ServicePrincipal"
}

resource "azurerm_postgresql_flexible_server_database" "sylo" {
  name      = "sylo"
  server_id = azurerm_postgresql_flexible_server.sylo.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_postgresql_flexible_server_database" "n8n" {
  name      = "n8n"
  server_id = azurerm_postgresql_flexible_server.sylo.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = true
  }
}

# --- Storage : Blob audio (cycle de vie 30 jours) et Queue agent-events. Clés partagées
# désactivées : accès par managed identity uniquement. Pare-feu de la queue : ADR-025, à ajouter
# avec l'IP du VPS une fois celle-ci confirmée.

resource "azurerm_storage_account" "sylo" {
  #checkov:skip=CKV_AZURE_59:Endpoint public conservé pour la queue lue depuis le VPS ; accès Entra uniquement, pare-feu à l'IP du VPS ensuite (ADR-025).
  #checkov:skip=CKV2_AZURE_33:Pas de private endpoint au MVP : coût fixe évité.
  #checkov:skip=CKV_AZURE_206:LRS par coût ; données reconstructibles.
  #checkov:skip=CKV2_AZURE_1:Clés gérées par Microsoft ; pas de CMK au MVP.
  #checkov:skip=CKV_AZURE_33:Journalisation de la queue : reportée.
  name                     = local.names.storage
  resource_group_name      = local.lz.resource_group.name
  location                 = local.lz.resource_group.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Suppression récupérable 7 jours : couvre l'effacement accidentel sans versioning (coût évité).
  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "audio" {
  #checkov:skip=CKV2_AZURE_21:Journalisation des lectures : reportée.
  name                  = "audio"
  storage_account_id    = azurerm_storage_account.sylo.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_queue" "agent_events" {
  name               = "agent-events"
  storage_account_id = azurerm_storage_account.sylo.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_management_policy" "audio" {
  storage_account_id = azurerm_storage_account.sylo.id

  rule {
    name    = "audio-30-jours"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["audio/"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
    }
  }
}

# Droits de l'API sur le storage : données blob et queue, sans clé.
resource "azurerm_role_assignment" "api_blob" {
  scope                = azurerm_storage_account.sylo.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.lz.workload_identities.api.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "api_queue" {
  scope                = azurerm_storage_account.sylo.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = local.lz.workload_identities.api.principal_id
  principal_type       = "ServicePrincipal"
}

# --- Container Apps : environnement Consumption intégré au VNet, trois applications.
# Les images sont publiées par la CI applicative ; Terraform ignore l'image et le port (ADR-011).

resource "azurerm_container_app_environment" "sylo" {
  name                       = local.names.environment
  resource_group_name        = local.lz.resource_group.name
  location                   = local.lz.resource_group.location
  logs_destination           = "log-analytics"
  log_analytics_workspace_id = local.lz.log_analytics_workspace_id
  infrastructure_subnet_id   = local.lz.network.aca_subnet_id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = local.tags
}

resource "azurerm_container_app" "app" {
  for_each = local.apps

  name                         = each.value.name
  resource_group_name          = local.lz.resource_group.name
  container_app_environment_id = azurerm_container_app_environment.sylo.id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [local.lz.workload_identities[each.key].id]
  }

  registry {
    server   = local.lz.container_registry.login_server
    identity = local.lz.workload_identities[each.key].id
  }

  ingress {
    external_enabled = true
    target_port      = 80
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = each.value.min_replicas
    max_replicas = each.value.max_replicas

    container {
      name   = each.key
      image  = var.placeholder_image
      cpu    = each.value.cpu
      memory = each.value.memory
    }
  }

  lifecycle {
    # La CI applicative publie les révisions et règle le port d'écoute réel.
    ignore_changes = [
      template[0].container[0].image,
      ingress[0].target_port,
    ]
  }
}

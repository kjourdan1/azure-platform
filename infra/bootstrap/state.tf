data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "tfstate" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                     = local.names.storage_account
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Aucune clé d'accès ni SAS : seules les identités Entra autorisées lisent le state.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Endpoint public conservé tant que les runners sont hébergés par GitHub (IP dynamiques).
  # Cible : runner self-hosted à IP fixe + network_rules en Deny. Voir docs/adr.
  public_network_access = "Enabled"

  blob_properties {
    # Chaque écriture du state crée une version : on peut revenir à un state antérieur.
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags

  # Détruire ce compte, c'est perdre le state de toute la plateforme.
  lifecycle {
    prevent_destroy = true
  }
}

# Avec storage_account_id, le conteneur est créé via ARM (management plane) :
# pas besoin de droit data plane pour ce premier apply.
resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# L'opérateur qui lance le bootstrap doit pouvoir lire/écrire le state
# pour la migration (terraform init -migrate-state) : droit data plane explicite.
resource "azurerm_role_assignment" "operator_state" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

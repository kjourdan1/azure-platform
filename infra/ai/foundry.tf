resource "azurerm_resource_group" "ai" {
  name     = "rg-${local.project}-ai-${local.suffix}"
  location = var.location
  tags     = local.tags
}

# Compte Foundry (nouveau modèle, sans hub) : un compte AIServices avec gestion de projets.
# Il porte modèles, projets, agents et évaluations sous une seule identité et une seule
# gouvernance. Aucun coût fixe : seul le token consommé est facturé, d'où une couche
# permanente, hors lab-up / lab-down.
resource "azurerm_cognitive_account" "foundry" {
  #checkov:skip=CKV_AZURE_134:Endpoint public tant que les runners sont hébergés ; accès Entra uniquement (clés désactivées)
  #checkov:skip=CKV2_AZURE_22:Chiffrement CMK : Key Vault et rotation à opérer, chiffrement Microsoft par défaut
  #checkov:skip=CKV_AZURE_247:Accès sortant non restreint : les agents Foundry à venir appelleront des outils externes (MCP) ; liste blanche à poser avec eux
  name                       = "aif-${local.project}-${local.suffix}"
  resource_group_name        = azurerm_resource_group.ai.name
  location                   = azurerm_resource_group.ai.location
  kind                       = "AIServices"
  sku_name                   = "S0"
  custom_subdomain_name      = "aif-${local.project}-${local.suffix}"
  project_management_enabled = true

  # Aucune clé d'API : authentification Entra ID uniquement, comme tout le reste du dépôt.
  local_auth_enabled            = false
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# Projet : l'espace de travail des équipes (agents, évaluations, connexions). Les
# déploiements de modèles restent au niveau du compte et sont partagés par les projets.
resource "azurerm_cognitive_account_project" "platform" {
  name                 = "azure-platform"
  cognitive_account_id = azurerm_cognitive_account.foundry.id
  location             = azurerm_resource_group.ai.location
  display_name         = "Azure Platform"
  description          = "Projet de la plateforme : socle des applications IA du cluster AKS."

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# Data Zone Standard : traitement garanti dans la zone UE (exigence fréquente des clients
# français), facturé au token. Version épinglée : un changement de modèle passe par une PR.
resource "azurerm_cognitive_deployment" "chat" {
  name                   = var.chat_model.name
  cognitive_account_id   = azurerm_cognitive_account.foundry.id
  version_upgrade_option = "NoAutoUpgrade"

  model {
    format  = "OpenAI"
    name    = var.chat_model.name
    version = var.chat_model.version
  }

  sku {
    name     = "DataZoneStandard"
    capacity = var.chat_capacity
  }
}

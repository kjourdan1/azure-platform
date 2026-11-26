locals {
  project     = "azpl"
  region_code = "frc"
  suffix      = "${var.environment}-${local.region_code}-001"

  lz = data.terraform_remote_state.lz_sylo.outputs

  names = {
    environment = "cae-${local.project}-sylo-${local.suffix}"
    postgres    = "psql-${local.project}-sylo-${local.suffix}"
    # Storage Account : alphanumérique, 24 caractères max.
    storage = "st${local.project}sylo${var.environment}${local.region_code}001"
  }

  tags = {
    owner         = "kjourdan1"
    "cost-center" = "sylo"
    environment   = var.environment
    project       = local.project
    "managed-by"  = "terraform"
    component     = "sylo"
  }

  # Charges applicatives (ADR-010, ADR-027). minReplicas = 0 pour web et api (démarrage à froid
  # accepté, NFR-004) ; n8n garde un réplica permanent (routines déterministes).
  apps = {
    api = {
      name         = "ca-sylo-api"
      min_replicas = 0
      max_replicas = 2
      cpu          = 0.5
      memory       = "1Gi"
    }
    web = {
      name         = "ca-sylo-web"
      min_replicas = 0
      max_replicas = 2
      cpu          = 0.5
      memory       = "1Gi"
    }
    n8n = {
      name         = "ca-sylo-n8n"
      min_replicas = 1
      max_replicas = 1
      cpu          = 0.5
      memory       = "1Gi"
    }
  }

  # Image et port d'écoute de chaque application : l'image de démarrage écoute sur 80.
  acr = local.lz.container_registry.login_server

  images = {
    api = {
      tagged = var.api_image_tag != ""
      image  = var.api_image_tag != "" ? "${local.acr}/sylo-api:${var.api_image_tag}" : var.placeholder_image
      port   = var.api_image_tag != "" ? 8000 : 80
    }
    web = {
      tagged = var.web_image_tag != ""
      image  = var.web_image_tag != "" ? "${local.acr}/sylo-cockpit:${var.web_image_tag}" : var.placeholder_image
      port   = var.web_image_tag != "" ? 3000 : 80
    }
    n8n = {
      tagged = var.n8n_image_tag != ""
      image  = var.n8n_image_tag != "" ? "docker.n8n.io/n8nio/n8n:${var.n8n_image_tag}" : var.placeholder_image
      port   = var.n8n_image_tag != "" ? 5678 : 80
    }
  }

  # Variables d'environnement de production (aucun secret : identités managées partout).
  app_env = {
    api = {
      ENVIRONMENT         = "prd"
      AUTH_MODE           = "entra"
      ENTRA_TENANT_ID     = data.azurerm_client_config.current.tenant_id
      ENTRA_API_CLIENT_ID = var.entra_api_client_id
      ENTRA_API_AUDIENCE  = var.entra_api_audience
      DB_AUTH_MODE        = "entra"
      # Utilisateur PostgreSQL = nom de l'identité de l'API, administrateur Entra du serveur.
      DATABASE_URL    = "postgresql+psycopg://id-${local.project}-sylo-api-${local.suffix}@${azurerm_postgresql_flexible_server.sylo.fqdn}:5432/sylo?sslmode=require"
      AZURE_CLIENT_ID = local.lz.workload_identities.api.client_id
    }
    web = {
      COCKPIT_STOCKAGE  = "sylo"
      SYLO_API_URL      = "https://ca-sylo-api.${azurerm_container_app_environment.sylo.default_domain}"
      SYLO_API_RESOURCE = var.entra_api_audience
      AZURE_CLIENT_ID   = local.lz.workload_identities.web.client_id
    }
    n8n = {
      DB_TYPE                               = "postgresdb"
      DB_POSTGRESDB_HOST                    = azurerm_postgresql_flexible_server.sylo.fqdn
      DB_POSTGRESDB_PORT                    = "5432"
      DB_POSTGRESDB_DATABASE                = "n8n"
      DB_POSTGRESDB_USER                    = "n8n"
      DB_POSTGRESDB_SSL_ENABLED             = "true"
      DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED = "false"
      N8N_PROTOCOL                          = "https"
      N8N_PORT                              = "5678"
      N8N_PROXY_HOPS                        = "1"
      WEBHOOK_URL                           = "https://ca-sylo-n8n.${azurerm_container_app_environment.sylo.default_domain}/"
      GENERIC_TIMEZONE                      = "Europe/Paris"
      TZ                                    = "Europe/Paris"
      N8N_DIAGNOSTICS_ENABLED               = "false"
      N8N_VERSION_NOTIFICATIONS_ENABLED     = "false"
      N8N_PERSONALIZATION_ENABLED           = "false"
      SYLO_API_URL                          = "http://ca-sylo-api"
    }
  }

  # Secrets n8n lus dans le Key Vault par l'identité de n8n (rôle Key Vault Secrets User, lz-sylo).
  # Clé = nom de la variable d'environnement ; valeur = nom du secret dans le Key Vault.
  n8n_secrets = {
    DB_POSTGRESDB_PASSWORD = "n8n-db-password"
    N8N_ENCRYPTION_KEY     = "n8n-encryption-key"
    QONTO_API_LOGIN        = "qonto-api-login"
    QONTO_API_SECRET       = "qonto-api-secret"
  }
}

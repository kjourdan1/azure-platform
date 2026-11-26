# --- Secrets et rôle PostgreSQL de n8n (ADR-027), générés par Terraform : aucun secret saisi à la main.
# Les valeurs vivent dans le Key Vault (lues par l'identité de n8n) et dans le state privé, comme le
# mot de passe administrateur PostgreSQL. Prérequis : droit « Key Vault Secrets Officer » de l'identité
# d'apply (stack lz-sylo).

resource "random_password" "n8n_db" {
  length  = 40
  special = false
}

resource "random_password" "n8n_encryption_key" {
  length  = 48
  special = false
}

resource "azurerm_key_vault_secret" "n8n_db_password" {
  #checkov:skip=CKV_AZURE_41:Pas d'expiration : le mot de passe est régénéré par Terraform, pas par date.
  name         = "n8n-db-password"
  value        = random_password.n8n_db.result
  key_vault_id = local.lz.key_vault.id
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "n8n_encryption_key" {
  #checkov:skip=CKV_AZURE_41:Clé de chiffrement de n8n : ne doit pas changer, sinon les identifiants stockés deviennent illisibles.
  name         = "n8n-encryption-key"
  value        = random_password.n8n_encryption_key.result
  key_vault_id = local.lz.key_vault.id
  content_type = "text/plain"

  lifecycle {
    prevent_destroy = true
  }
}

# Rôle PostgreSQL « n8n » (seule exception à l'authentification Entra, ADR-027) : créé par un job à
# déclenchement manuel dans l'environnement privé, avec le compte administrateur. Idempotent ; relancé
# quand le mot de passe change. Le rôle possède la base n8n et n'a aucun droit sur la base sylo.
resource "azurerm_container_app_job" "n8n_bootstrap" {
  name                         = "caj-sylo-n8n-bootstrap"
  location                     = local.lz.resource_group.location
  resource_group_name          = local.lz.resource_group.name
  container_app_environment_id = azurerm_container_app_environment.sylo.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 300
  replica_retry_limit          = 1
  tags                         = local.tags

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  secret {
    name  = "pgpassword"
    value = random_password.pg_admin.result
  }

  secret {
    name  = "n8n-pw"
    value = random_password.n8n_db.result
  }

  template {
    container {
      name   = "bootstrap"
      image  = "postgres:16-alpine"
      cpu    = 0.25
      memory = "0.5Gi"

      command = ["/bin/sh", "-c"]
      args = [<<-EOT
        psql -v ON_ERROR_STOP=1 -v pw="$N8N_PW" <<'SQL'
        SELECT format('CREATE ROLE n8n LOGIN PASSWORD %L', :'pw') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'n8n') \gexec
        SELECT format('ALTER ROLE n8n PASSWORD %L', :'pw') \gexec
        GRANT n8n TO syloadmin;
        ALTER DATABASE n8n OWNER TO n8n;
        SQL
      EOT
      ]

      env {
        name  = "PGHOST"
        value = azurerm_postgresql_flexible_server.sylo.fqdn
      }
      env {
        name  = "PGUSER"
        value = "syloadmin"
      }
      env {
        name  = "PGDATABASE"
        value = "postgres"
      }
      env {
        name  = "PGSSLMODE"
        value = "require"
      }
      env {
        name        = "PGPASSWORD"
        secret_name = "pgpassword"
      }
      env {
        name        = "N8N_PW"
        secret_name = "n8n-pw"
      }
    }
  }
}

resource "terraform_data" "n8n_bootstrap_trigger" {
  input = sha256(random_password.n8n_db.result)
}

resource "azapi_resource_action" "n8n_bootstrap_start" {
  type        = "Microsoft.App/jobs@2024-03-01"
  resource_id = azurerm_container_app_job.n8n_bootstrap.id
  action      = "start"
  method      = "POST"

  depends_on = [azurerm_postgresql_flexible_server_database.n8n]

  lifecycle {
    replace_triggered_by = [terraform_data.n8n_bootstrap_trigger]
  }
}

output "container_app_environment" {
  description = "Environnement Container Apps de Sylo."
  value = {
    id             = azurerm_container_app_environment.sylo.id
    default_domain = azurerm_container_app_environment.sylo.default_domain
  }
}

output "applications" {
  description = "FQDN d'entrée de chaque application, par clé (api, web, n8n)."
  value = {
    for k, v in azurerm_container_app.app : k => v.ingress[0].fqdn
  }
}

output "postgres" {
  description = "Serveur PostgreSQL privé (FQDN résolu dans le VNet uniquement)."
  value = {
    id   = azurerm_postgresql_flexible_server.sylo.id
    fqdn = azurerm_postgresql_flexible_server.sylo.fqdn
  }
}

output "storage_account" {
  description = "Compte de stockage de Sylo (blob audio, queue agent-events)."
  value = {
    id   = azurerm_storage_account.sylo.id
    name = azurerm_storage_account.sylo.name
  }
}

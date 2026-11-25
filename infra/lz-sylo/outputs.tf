output "resource_group" {
  description = "Resource group de Sylo."
  value = {
    id       = azurerm_resource_group.sylo.id
    name     = azurerm_resource_group.sylo.name
    location = azurerm_resource_group.sylo.location
  }
}

output "subscription_id" {
  description = "Subscription azpl-lz-sylo."
  value       = data.azurerm_client_config.current.subscription_id
}

output "network" {
  description = "Sous-réseaux délégués et zone DNS privée de PostgreSQL."
  value = {
    aca_subnet_id   = azurerm_subnet.aca.id
    pg_subnet_id    = azurerm_subnet.pg.id
    pg_dns_zone_id  = azurerm_private_dns_zone.pg.id
    virtual_network = azurerm_virtual_network.sylo.id
  }
}

output "log_analytics_workspace_id" {
  description = "Workspace Log Analytics de l'environnement Container Apps."
  value       = azurerm_log_analytics_workspace.sylo.id
}

output "key_vault" {
  description = "Key Vault de Sylo (RBAC)."
  value = {
    id        = azurerm_key_vault.sylo.id
    name      = azurerm_key_vault.sylo.name
    vault_uri = azurerm_key_vault.sylo.vault_uri
  }
}

output "container_registry" {
  description = "ACR Basic de Sylo."
  value = {
    id           = azurerm_container_registry.sylo.id
    login_server = azurerm_container_registry.sylo.login_server
  }
}

output "workload_identities" {
  description = "Identités managées des charges, par clé (api, web, n8n)."
  value = {
    for k, v in azurerm_user_assigned_identity.workload : k => {
      id           = v.id
      client_id    = v.client_id
      principal_id = v.principal_id
    }
  }
}

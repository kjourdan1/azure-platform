output "aks_nodes_subnet_id" {
  description = "Subnet des nœuds AKS."
  value       = azurerm_subnet.aks_nodes.id
}

output "key_vault_id" {
  description = "Key Vault du chemin des secrets."
  value       = azurerm_key_vault.aks.id
}

output "container_registry_id" {
  description = "Registre d'images du cluster."
  value       = azurerm_container_registry.aks.id
}

# À copier dans le secret AZURE_CLIENT_ID_LAB de l'environnement GitHub lab.
output "lab_client_id" {
  description = "Client ID de l'identité lab-down."
  value       = azurerm_user_assigned_identity.lab.client_id
  sensitive   = true
}

output "subscription_id" {
  description = "Subscription azpl-lz-aks (external-dns en a besoin pour écrire dans la zone)."
  value       = data.azurerm_subscription.lz_aks.subscription_id
  sensitive   = true
}

output "key_vault_uri" {
  description = "URI du coffre, pour le ClusterSecretStore d'External Secrets."
  value       = azurerm_key_vault.aks.vault_uri
}

output "dns_zone" {
  description = "Sous-zone publique du lab."
  value = {
    id                  = azurerm_dns_zone.lab.id
    name                = azurerm_dns_zone.lab.name
    resource_group_name = azurerm_dns_zone.lab.resource_group_name
  }
}

# À reporter une fois chez IONOS : enregistrements NS de l'hôte « lab ».
output "dns_zone_name_servers" {
  description = "Serveurs de noms de la sous-zone, à déléguer depuis IONOS."
  value       = azurerm_dns_zone.lab.name_servers
}

output "workload_identities" {
  description = "Identités des contrôleurs (ID de ressource et client ID), par clé."
  value = {
    for k, id in azurerm_user_assigned_identity.workload : k => {
      id        = id.id
      client_id = id.client_id
    }
  }
  sensitive = true
}

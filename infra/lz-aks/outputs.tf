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

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

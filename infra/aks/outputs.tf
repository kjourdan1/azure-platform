output "cluster_name" {
  description = "Nom du cluster (az aks get-credentials)."
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_resource_group" {
  description = "Resource group du cluster."
  value       = azurerm_resource_group.cluster.name
}

output "oidc_issuer_url" {
  description = "Émetteur OIDC du cluster, pour les credentials fédérés de Workload Identity."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

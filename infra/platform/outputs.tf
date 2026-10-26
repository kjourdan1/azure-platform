output "log_analytics_workspace_id" {
  description = "ID du workspace Log Analytics de la plateforme."
  value       = azurerm_log_analytics_workspace.platform.id
}

output "hub_virtual_network" {
  description = "VNet hub, cible du peering des spokes."
  value = {
    id                  = azurerm_virtual_network.hub.id
    name                = azurerm_virtual_network.hub.name
    resource_group_name = azurerm_resource_group.connectivity.name
  }
}

# Requêtes, audit et consommation de tokens vers le Log Analytics central (couche platform) :
# la base de l'observabilité et du FinOps de l'IA (qui consomme quoi, avec quel modèle).
resource "azurerm_monitor_diagnostic_setting" "foundry" {
  name                       = "to-platform-law"
  target_resource_id         = azurerm_cognitive_account.foundry.id
  log_analytics_workspace_id = data.terraform_remote_state.platform.outputs.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

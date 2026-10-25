resource "azurerm_resource_group" "management" {
  name     = "rg-${local.project}-management-${local.suffix}"
  location = var.location
  tags     = local.tags
}

# Workspace central : diagnostics de la plateforme et du cluster AKS. Coût à l'ingestion
# uniquement ; le plafond journalier et la rétention de 30 jours (incluse) bornent la
# facture fantôme citée dans le cadrage.
resource "azurerm_log_analytics_workspace" "platform" {
  name                = "law-${local.project}-platform-${local.suffix}"
  resource_group_name = azurerm_resource_group.management.name
  location            = azurerm_resource_group.management.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_analytics_daily_quota_gb
  tags                = local.tags
}

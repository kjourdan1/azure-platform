# Sous-zone publique des services du cluster. external-dns y écrit les enregistrements à
# chaque lab-up (l'IP du load balancer change avec le cluster). Azure DNS plutôt que l'API
# IONOS : une clé API IONOS donne accès à tout le compte (portfolio, autres domaines) et
# devrait être stockée ; ici l'écriture passe par Workload Identity, limitée à cette zone.
# Permanente : la recréer changerait ses serveurs de noms et casserait la délégation.
resource "azurerm_dns_zone" "lab" {
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

output "resource_group" {
  description = "Resource group d'accueil du portfolio, cible du déplacement."
  value = {
    id   = azurerm_resource_group.web.id
    name = azurerm_resource_group.web.name
  }
}

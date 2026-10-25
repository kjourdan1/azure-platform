resource "azurerm_resource_group" "connectivity" {
  name     = "rg-${local.project}-connectivity-${local.suffix}"
  location = var.location
  tags     = local.tags
}

# Hub sans pare-feu ni passerelle : Azure Firewall, Bastion et VPN Gateway restent au
# stade plan (coût). Le hub porte le peering des spokes et accueillera le DNS privé.
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${local.project}-hub-${local.suffix}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = azurerm_resource_group.connectivity.location
  address_space       = [var.hub_address_space]
  tags                = local.tags
}

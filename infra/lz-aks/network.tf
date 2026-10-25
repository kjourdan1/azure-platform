# Ressources permanentes partagées par le cluster : le cluster lui-même vivra dans son
# propre resource group, créé et détruit à la demande (lab-up / lab-down).
resource "azurerm_resource_group" "shared" {
  name     = "rg-${local.project}-aks-shared-${local.suffix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-${local.project}-aks-${local.suffix}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  address_space       = [var.spoke_address_space]
  tags                = local.tags
}

# Seul le trafic web entrant est ouvert depuis Internet, vers l'ingress du cluster.
resource "azurerm_network_security_group" "aks_nodes" {
  #checkov:skip=CKV_AZURE_160:Port 80 requis par l'ingress : redirection HTTPS et challenge ACME HTTP-01 de cert-manager
  name                = "nsg-${local.project}-aks-nodes-${local.suffix}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  tags                = local.tags

  security_rule {
    name                       = "allow-web-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "Internet"
    source_port_range          = "*"
    destination_address_prefix = var.aks_nodes_subnet_prefix
    destination_port_ranges    = ["80", "443"]
  }
}

# La policy ALZ Deny-Subnet-Without-Nsg refuse un subnet créé sans NSG : l'association
# est passée à la création (attribut write-only), pas dans une ressource séparée.
resource "azurerm_subnet" "aks_nodes" {
  name                                 = "snet-${local.project}-aks-nodes-${local.suffix}"
  resource_group_name                  = azurerm_resource_group.shared.name
  virtual_network_name                 = azurerm_virtual_network.spoke.name
  address_prefixes                     = [var.aks_nodes_subnet_prefix]
  network_security_group_id_wo         = azurerm_network_security_group.aks_nodes.id
  network_security_group_id_wo_version = 1
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-aks-to-hub"
  resource_group_name       = azurerm_resource_group.shared.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = local.hub.id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  provider = azurerm.platform

  name                      = "peer-hub-to-aks"
  resource_group_name       = local.hub.resource_group_name
  virtual_network_name      = local.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic   = true
}

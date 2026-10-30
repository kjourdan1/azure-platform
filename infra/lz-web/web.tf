# Resource group d'accueil du portfolio (reprise brownfield, docs/runbooks/brownfield-lab.md).
# Il doit exister et être conforme avant le déplacement de la Static Web App depuis LAB ;
# la Static Web App y sera ensuite importée, pas recréée.
resource "azurerm_resource_group" "web" {
  name     = "rg-${local.project}-web-${local.suffix}"
  location = var.location
  tags     = local.tags
}

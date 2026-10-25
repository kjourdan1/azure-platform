# Registre des images du cluster. SKU Basic (~5 €/mois, permanent) : les fonctions
# Premium remontées par checkov (géo-réplication, private endpoint, CMK, quarantaine,
# rétention) ne justifient pas un SKU à ~45 €/mois pour un lab.
resource "azurerm_container_registry" "aks" {
  #checkov:skip=CKV_AZURE_139:Accès public requis par les runners hébergés (push CI) ; auth Entra uniquement
  #checkov:skip=CKV_AZURE_165:Géo-réplication : Premium uniquement
  #checkov:skip=CKV_AZURE_166:Quarantaine des images : Premium uniquement
  #checkov:skip=CKV_AZURE_167:Rétention des images non taguées : Premium uniquement
  #checkov:skip=CKV_AZURE_233:Redondance de zone : Premium uniquement
  #checkov:skip=CKV_AZURE_237:Endpoints de données dédiés : Premium uniquement
  #checkov:skip=CKV2_AZURE_1:Chiffrement CMK : Premium uniquement
  #checkov:skip=CKV_AZURE_164:Content trust (images signées) : Premium uniquement
  #checkov:skip=CKV_AZURE_163:Scan via Defender for Containers (payant) ; scan Trivy prévu en CI
  name                   = "acr${local.project}aks${replace(local.suffix, "-", "")}"
  resource_group_name    = azurerm_resource_group.shared.name
  location               = azurerm_resource_group.shared.location
  sku                    = "Basic"
  admin_enabled          = false
  anonymous_pull_enabled = false
  tags                   = local.tags
}

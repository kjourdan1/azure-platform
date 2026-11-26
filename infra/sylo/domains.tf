# --- Domaines personnalisés du cockpit (app) et de l'API (api), certificats gérés par Azure.
# La zone DNS de sylo.sh reste chez le registrar (elle porte aussi le courrier) : les
# enregistrements sont à créer à la main, en deux temps.
#   1. enable_custom_domains = false : appliquer, lire la sortie custom_domain_dns_records,
#      créer les enregistrements chez le registrar.
#   2. enable_custom_domains = true : appliquer, Azure vérifie le DNS, lie les domaines et émet
#      les certificats (validation CNAME).
# Après la bascule, ajouter https://<app_hostname>/.auth/login/aad/callback aux URI de
# redirection de l'application Entra sylo-web.

variable "app_hostname" {
  description = "Nom de domaine du cockpit."
  type        = string
  default     = "app.sylo.sh"
}

variable "api_hostname" {
  description = "Nom de domaine de l'API (protégée par Entra OAuth2)."
  type        = string
  default     = "api.sylo.sh"
}

variable "enable_custom_domains" {
  description = "Lie les domaines et crée les certificats gérés. À activer une fois les enregistrements DNS en place."
  type        = bool
  default     = false
}

locals {
  custom_domains = {
    web = var.app_hostname
    api = var.api_hostname
  }
}

resource "azurerm_container_app_custom_domain" "domain" {
  for_each = var.enable_custom_domains ? local.custom_domains : {}

  name             = each.value
  container_app_id = azurerm_container_app.app[each.key].id

  lifecycle {
    # Le certificat géré est lié par Azure, de façon asynchrone : ne pas recréer le domaine.
    ignore_changes = [certificate_binding_type, container_app_environment_certificate_id]
  }
}

resource "azurerm_container_app_environment_managed_certificate" "domain" {
  for_each = var.enable_custom_domains ? local.custom_domains : {}

  name                         = "mc-${each.key}"
  container_app_environment_id = azurerm_container_app_environment.sylo.id
  subject_name                 = each.value
  domain_control_validation    = "CNAME"
  tags                         = local.tags

  depends_on = [azurerm_container_app_custom_domain.domain]
}

output "custom_domain_dns_records" {
  description = "Enregistrements DNS à créer chez le registrar pour les domaines personnalisés."
  value = merge(
    {
      for k, host in local.custom_domains : "cname_${k}" => {
        type  = "CNAME"
        name  = host
        value = azurerm_container_app.app[k].ingress[0].fqdn
      }
    },
    {
      for k, host in local.custom_domains : "txt_${k}" => {
        type  = "TXT"
        name  = "asuid.${host}"
        value = azurerm_container_app_environment.sylo.custom_domain_verification_id
      }
    }
  )
}

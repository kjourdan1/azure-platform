# Reprise brownfield de la subscription du state (docs/runbooks/brownfield-lab.md) :
# rattachée au management group management de la landing zone, renommée selon son usage,
# Defender aligné sur ce qui est réellement exploité. Ces actions touchent la subscription
# du state : elles vivent ici, appliquées par l'opérateur, jamais par la CI.
locals {
  management_subscription_name = "azpl-management"
}

# Prérequis appliqué avant (runbook, revue des droits) : l'identité apply a perdu l'Owner
# implicite qu'Azure donne au créateur d'un management group. Sans cela, ce rattachement
# la rendrait Owner de la subscription du state par héritage.
resource "azapi_resource_action" "management_group_association" {
  method      = "PUT"
  resource_id = "/providers/Microsoft.Management/managementGroups/management/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  type        = "Microsoft.Management/managementGroups/subscriptions@2021-04-01"
}

# Même action que le module de vending pour les autres subscriptions.
resource "azapi_resource_action" "rename" {
  action      = "providers/Microsoft.Subscription/rename"
  method      = "POST"
  resource_id = data.azurerm_subscription.current.id
  type        = "Microsoft.Resources/subscriptions@2021-10-01"
  body = {
    subscriptionName = local.management_subscription_name
  }
}

# Defender CSPM (plan CloudPosture), seul plan Defender facturé sur cette subscription
# (0,64 € en octobre, désactivé à la main le 26) : le niveau gratuit est fixé en code pour
# qu'une réactivation hors code apparaisse en dérive. Discovery et FoundationalCspm sont des
# plans de base gratuits que l'API n'accepte qu'en Standard : on ne les gère pas.
resource "azapi_update_resource" "defender_cspm" {
  type        = "Microsoft.Security/pricings@2024-01-01"
  resource_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Security/pricings/CloudPosture"
  body = {
    properties = {
      pricingTier = "Free"
    }
  }
}

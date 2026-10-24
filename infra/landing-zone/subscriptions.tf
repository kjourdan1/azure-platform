locals {
  # azpl-lz-aks va dans online et non corp : l'ingress AKS est public, que corp interdit.
  subscriptions = {
    platform = { id = var.subscription_ids.platform, management_group = "platform" }
    lz_aks   = { id = var.subscription_ids.lz_aks, management_group = "online" }
  }

  # Resource providers enregistrés à la création de la subscription (rôle du "vending") :
  # les couches suivantes n'ont pas à porter ce droit.
  resource_providers = [
    "Microsoft.Consumption",
    "Microsoft.ContainerRegistry",
    "Microsoft.ContainerService",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
  ]

  provider_registrations = {
    for pair in setproduct(keys(local.subscriptions), local.resource_providers) :
    "${pair[0]}-${pair[1]}" => { subscription = pair[0], namespace = pair[1] }
  }

  # Alertes à 10, 25 et 50 € (20/50/100 % de 50 €), plus une alerte sur la prévision.
  budget_notifications = {
    actual-20    = { threshold = 20, type = "Actual" }
    actual-50    = { threshold = 50, type = "Actual" }
    actual-100   = { threshold = 100, type = "Actual" }
    forecast-100 = { threshold = 100, type = "Forecasted" }
  }
}

resource "azapi_resource_action" "provider_registration" {
  for_each = local.provider_registrations

  type        = "Microsoft.Resources/subscriptions@2022-12-01"
  resource_id = "/subscriptions/${local.subscriptions[each.value.subscription].id}"
  action      = "providers/${each.value.namespace}/register"
  method      = "POST"
}

resource "azapi_resource" "budget" {
  for_each = local.subscriptions

  type      = "Microsoft.Consumption/budgets@2023-11-01"
  name      = "budget-azpl-${replace(each.key, "_", "-")}-prd"
  parent_id = "/subscriptions/${each.value.id}"

  body = {
    properties = {
      category   = "Cost"
      amount     = var.budget_amount
      timeGrain  = "Monthly"
      timePeriod = { startDate = var.budget_start_date }
      # Envoyé aux Owners de la subscription : aucune adresse e-mail dans le code.
      notifications = {
        for name, n in local.budget_notifications : name => {
          enabled       = true
          operator      = "GreaterThanOrEqualTo"
          threshold     = n.threshold
          thresholdType = n.type
          contactRoles  = ["Owner"]
          contactEmails = []
        }
      }
    }
  }

  depends_on = [azapi_resource_action.provider_registration]
}

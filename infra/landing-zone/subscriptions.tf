locals {
  subscriptions = {
    platform = {
      alias_name = "azpl-platform"
      # Management group direct : héberge le futur réseau hub et Log Analytics.
      management_group = "platform"
    }
    lz_aks = {
      alias_name = "azpl-lz-aks"
      # online et non corp : l'ingress AKS est public, que corp interdit.
      management_group = "online"
    }
  }

  # Resource providers nécessaires aux couches suivantes (réseau, AKS, ACR, Key Vault,
  # observabilité), enregistrés au moment de la vente : les couches suivantes n'ont pas
  # à porter ce droit.
  resource_providers = {
    "Microsoft.Consumption"         = []
    "Microsoft.ContainerRegistry"   = []
    "Microsoft.ContainerService"    = []
    "Microsoft.Insights"            = []
    "Microsoft.KeyVault"            = []
    "Microsoft.ManagedIdentity"     = []
    "Microsoft.Network"             = []
    "Microsoft.OperationalInsights" = []
  }

  # Alertes à 10, 25 et 50 € (20/50/100 % de 50 €), plus une alerte sur la prévision.
  budget_notifications = {
    actual-20    = { threshold = 20, type = "Actual" }
    actual-50    = { threshold = 50, type = "Actual" }
    actual-100   = { threshold = 100, type = "Actual" }
    forecast-100 = { threshold = 100, type = "Forecasted" }
  }
}

# Crée azpl-platform et azpl-lz-aks par alias de subscription (le créateur, ici
# l'identité apply, en devient Owner automatiquement — aucune attribution de rôle
# supplémentaire n'est nécessaire), les place dans leur management group et enregistre
# les resource providers dont les couches suivantes auront besoin.
module "subscriptions" {
  source   = "Azure/avm-ptn-alz-sub-vending/azure"
  version  = "0.3.4"
  for_each = local.subscriptions

  enable_telemetry = false

  subscription_alias_enabled = true
  subscription_alias_name    = each.value.alias_name
  subscription_display_name  = each.value.alias_name
  subscription_billing_scope = var.subscription_billing_scope
  subscription_workload      = "Production"

  subscription_management_group_association_enabled = true
  subscription_management_group_id                  = each.value.management_group

  subscription_register_resource_providers_enabled      = true
  subscription_register_resource_providers_and_features = local.resource_providers

  subscription_tags = {
    owner         = "kjourdan1"
    "cost-center" = "azure-platform"
    project       = "azpl"
    "managed-by"  = "terraform"
  }
}

# Budget unique sur le management group "alz" : couvre platform et landingzones, donc
# les deux subscriptions ci-dessus, sans jamais inclure LAB qui reste à la racine du
# tenant (state, portfolio hors plateforme).
resource "azapi_resource" "budget" {
  type      = "Microsoft.Consumption/budgets@2023-11-01"
  name      = "budget-azpl-lab-prd"
  parent_id = "/providers/Microsoft.Management/managementGroups/alz"

  body = {
    properties = {
      category   = "Cost"
      amount     = var.budget_amount
      timeGrain  = "Monthly"
      timePeriod = { startDate = var.budget_start_date }
      notifications = {
        for name, n in local.budget_notifications : name => {
          enabled       = true
          operator      = "GreaterThanOrEqualTo"
          threshold     = n.threshold
          thresholdType = n.type
          # Un rôle seul (Owner) ne suffit pas à l'échelle management group : l'API
          # Consumption Budgets y exige un e-mail explicite.
          contactEmails = [var.budget_alert_email]
        }
      }
    }
  }

  depends_on = [module.alz]
}

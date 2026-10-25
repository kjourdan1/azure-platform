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

  # Par subscription : alertes à 10, 25 et 50 € (20/50/100 % de 50 €), plus la prévision.
  budget_notifications = {
    actual-20    = { threshold = 20, type = "Actual" }
    actual-50    = { threshold = 50, type = "Actual" }
    actual-100   = { threshold = 100, type = "Actual" }
    forecast-100 = { threshold = 100, type = "Forecasted" }
  }
}

# Crée azpl-platform et azpl-lz-aks par alias de subscription (le créateur, ici
# l'identité apply, en devient Owner automatiquement — aucune attribution de rôle
# supplémentaire n'est nécessaire), les place dans leur management group, enregistre
# les resource providers dont les couches suivantes auront besoin et pose leur budget.
module "subscriptions" {
  # Épinglé par commit (tag v0.3.4), comme le module ALZ.
  source   = "git::https://github.com/Azure/terraform-azure-avm-ptn-alz-sub-vending.git?ref=28577b03cf4ad2cd5faa2e9ee7991f07c7c2dab0"
  for_each = local.subscriptions

  location         = var.location
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

  # Budget par subscription : Cost Management ne supporte pas les management groups
  # pour les subscriptions MCA, et un budget au niveau billing profile inclurait LAB.
  budget_enabled = true
  budgets = {
    monthly = {
      name              = "budget-azpl-${replace(each.key, "_", "-")}-prd"
      amount            = var.budget_amount
      time_grain        = "Monthly"
      time_period_start = var.budget_start_date
      time_period_end   = var.budget_end_date
      notifications = {
        for name, n in local.budget_notifications : name => {
          enabled        = true
          operator       = "GreaterThanOrEqualTo"
          threshold      = n.threshold
          threshold_type = n.type
          # L'Owner d'une subscription créée par alias est l'identité apply, sans
          # boîte mail : l'alerte part vers un e-mail explicite (secret, masqué au plan).
          contact_emails = [var.budget_alert_email]
        }
      }
    }
  }

  subscription_tags = {
    owner         = "kjourdan1"
    "cost-center" = "azure-platform"
    project       = "azpl"
    "managed-by"  = "terraform"
  }
}

locals {
  # Subscriptions existantes, gérées par leur ID retrouvé par leur nom. Pour en créer
  # une nouvelle : réintroduire temporairement la ressource subscription_alias (commit
  # e61e625), puis la retirer du state par un bloc removed une fois la création faite.
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

  subscription_tags = {
    owner         = "kjourdan1"
    "cost-center" = "azure-platform"
    project       = "azpl"
    "managed-by"  = "terraform"
  }

  # Resource providers nécessaires aux couches suivantes (réseau, AKS, ACR, Key Vault,
  # observabilité, IA), enregistrés au moment de la vente : les couches suivantes n'ont pas
  # à porter ce droit.
  resource_providers = {
    "Microsoft.CognitiveServices"       = []
    "Microsoft.Consumption"             = []
    "Microsoft.ContainerRegistry"       = []
    "Microsoft.ContainerService"        = []
    "Microsoft.Insights"                = []
    "Microsoft.KeyVault"                = []
    "Microsoft.KubernetesConfiguration" = []
    "Microsoft.ManagedIdentity"         = []
    "Microsoft.Network"                 = []
    "Microsoft.OperationalInsights"     = []
  }

  # Par subscription : alertes à 10, 25 et 50 € (20/50/100 % de 50 €), plus la prévision.
  budget_notifications = {
    actual-20    = { threshold = 20, type = "Actual" }
    actual-50    = { threshold = 50, type = "Actual" }
    actual-100   = { threshold = 100, type = "Actual" }
    forecast-100 = { threshold = 100, type = "Forecasted" }
  }
}

# Alias de création retiré du state sans appel à Azure : Azure exige le droit
# Microsoft.Subscription/aliases/write pour simplement lire un alias, ce que l'identité
# de plan des PR n'a pas. La subscription reste : un alias n'est que le nom de la demande
# de création. Pas de destruction non plus : le droit de supprimer un alias n'est pas acquis.
removed {
  from = azapi_resource.subscription_alias

  lifecycle {
    destroy = false
  }
}

# Subscriptions existantes retrouvées par leur nom : aucun ID dans le code. Les
# subscriptions annulées (même nom, état Disabled) sont écartées.
data "azapi_resource_list" "subscriptions" {
  type      = "Microsoft.Resources/subscriptions@2022-12-01"
  parent_id = "/"

  response_export_values = {
    enabled = "value[?state == 'Enabled'].{name: displayName, id: subscriptionId}"
  }
}

locals {
  existing_subscription_ids = { for sub in data.azapi_resource_list.subscriptions.output.enabled : sub.name => sub.id }

  subscription_ids = { for key, sub in local.subscriptions : key => local.existing_subscription_ids[sub.alias_name] }
}

# L'ancien appel gérait aussi l'alias : il est oublié sans rien détruire. Son state ne
# contenait que l'alias de azpl-lz-aks, avant toute action d'annulation.
removed {
  from = module.subscriptions

  lifecycle {
    destroy = false
  }
}

# Gouvernance des subscriptions existantes : placement dans leur management group,
# resource providers nécessaires aux couches suivantes, tags et budget.
module "vended_subscriptions" {
  # Épinglé par commit (tag v0.3.4), comme le module ALZ.
  source   = "git::https://github.com/Azure/terraform-azure-avm-ptn-alz-sub-vending.git?ref=28577b03cf4ad2cd5faa2e9ee7991f07c7c2dab0"
  for_each = local.subscriptions

  location         = var.location
  enable_telemetry = false

  subscription_alias_enabled   = false
  subscription_id              = local.subscription_ids[each.key]
  subscription_display_name    = each.value.alias_name
  subscription_update_existing = true
  subscription_tags            = local.subscription_tags

  subscription_management_group_association_enabled = true
  subscription_management_group_id                  = each.value.management_group

  subscription_register_resource_providers_enabled      = true
  subscription_register_resource_providers_and_features = local.resource_providers

  # Budget par subscription : Cost Management ne supporte pas les management groups
  # pour les subscriptions MCA. Le budget global (bootstrap) couvre l'ensemble.
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
}

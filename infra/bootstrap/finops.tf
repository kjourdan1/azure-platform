locals {
  # Le profil de facturation est le parent de l'invoice section passée en secret.
  billing_profile_id = regex("^(.*/billingProfiles/[^/]+)", var.subscription_billing_scope)[0]

  # Pourcentages du budget global : alertes sur le réel, plus la prévision à 100 %.
  global_budget_notifications = {
    actual_50    = { threshold = 50, type = "Actual" }
    actual_80    = { threshold = 80, type = "Actual" }
    actual_100   = { threshold = 100, type = "Actual" }
    forecast_100 = { threshold = 100, type = "Forecasted" }
  }
}

# Budget global, LAB comprise : Cost Management ne supporte pas les management groups
# pour un contrat MCA, le profil de facturation est le seul scope qui couvre tout. Il vit
# dans le bootstrap car il exige un rôle de facturation que la CI n'a pas.
# Le plan des PR doit pouvoir le relire : l'identité plan reçoit « Billing profile reader »
# à la main (l'API de facturation n'expose pas de PUT pour ce rôle, seulement une action).
resource "azapi_resource" "global_budget" {
  type      = "Microsoft.Consumption/budgets@2023-05-01"
  name      = "budget-${local.project}-global"
  parent_id = local.billing_profile_id

  body = {
    properties = {
      category  = "Cost"
      amount    = var.global_budget_amount
      timeGrain = "Monthly"
      timePeriod = {
        startDate = var.budget_start_date
        endDate   = var.budget_end_date
      }
      notifications = {
        for name, n in local.global_budget_notifications : name => {
          enabled       = true
          operator      = "GreaterThanOrEqualTo"
          threshold     = n.threshold
          thresholdType = n.type
          contactEmails = [var.budget_alert_email]
        }
      }
    }
  }
}

# LAB est hors de la hiérarchie ALZ : son alerte d'anomalie se déclare ici.
resource "azapi_resource" "lab_anomaly_alert" {
  type      = "Microsoft.CostManagement/scheduledActions@2023-11-01"
  name      = "anomaly-${local.project}-lab"
  parent_id = data.azurerm_subscription.current.id

  body = {
    kind = "InsightAlert"
    properties = {
      displayName = "Cost anomaly LAB"
      status      = "Enabled"
      viewId      = "${data.azurerm_subscription.current.id}/providers/Microsoft.CostManagement/views/ms:DailyAnomalyByResourceGroup"
      notification = {
        to      = [var.budget_alert_email]
        subject = "Cost anomaly LAB"
      }
      schedule = {
        frequency = "Daily"
        startDate = var.anomaly_alert_start_date
        endDate   = var.budget_end_date
      }
    }
  }
}

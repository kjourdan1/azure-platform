variable "location" {
  description = "Région des identités managées créées pour les policies DeployIfNotExists."
  type        = string
  default     = "francecentral"
}

variable "security_contact_email" {
  description = "Contact Defender for Cloud, porté par la policy Deploy-MDFC-Config."
  type        = string
  default     = "security@azure-platform.invalid"
}

# Scope MCA (invoice section) où les subscriptions sont vendues : fourni par un secret
# GitHub, jamais dans le code. sensitive pour que Terraform le masque dans le plan.
variable "subscription_billing_scope" {
  description = "Billing scope MCA (invoice section) pour la création des subscriptions par alias."
  type        = string
  sensitive   = true
}

# Destinataire des alertes de budget : un secret, pas un rôle, car l'API Consumption
# Budgets exige un e-mail explicite à l'échelle management group.
variable "budget_alert_email" {
  description = "E-mail de notification des alertes de budget."
  type        = string
  sensitive   = true
}

variable "budget_amount" {
  description = "Budget mensuel total du lab (les deux subscriptions comprises), en devise de facturation."
  type        = number
  default     = 50
}

variable "budget_start_date" {
  description = "Début des budgets : premier jour d'un mois, format RFC 3339."
  type        = string
  default     = "2026-10-01T00:00:00Z"
}

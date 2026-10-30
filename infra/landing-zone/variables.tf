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

# Destinataire des alertes de budget : un secret, pas un rôle, car l'Owner d'une
# subscription créée par alias est l'identité apply, qui n'a pas de boîte mail.
variable "budget_alert_email" {
  description = "E-mail de notification des alertes de budget."
  type        = string
  sensitive   = true
}

variable "budget_amount" {
  description = "Budget mensuel par subscription, en devise de facturation."
  type        = number
  default     = 50
}

variable "budget_start_date" {
  description = "Début des budgets : premier jour d'un mois, format RFC 3339."
  type        = string
  default     = "2026-10-01T00:00:00Z"
}

variable "budget_end_date" {
  description = "Fin des budgets, format RFC 3339 (exigée par le module de vending)."
  type        = string
  default     = "2027-12-31T23:59:59Z"
}

variable "anomaly_alert_start_date" {
  description = "Début des alertes d'anomalie de coût, format RFC 3339."
  type        = string
  default     = "2026-11-01T00:00:00Z"
}

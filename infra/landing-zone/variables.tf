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

# IDs fournis par des secrets GitHub (TF_VAR_subscription_ids) : jamais dans le code.
variable "subscription_ids" {
  description = "Subscriptions de la plateforme : platform (management, réseau hub) et lz_aks (workload AKS)."
  type = object({
    platform = string
    lz_aks   = string
  })
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

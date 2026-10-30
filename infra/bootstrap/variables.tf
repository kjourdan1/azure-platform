variable "location" {
  description = "Région Azure des ressources du bootstrap."
  type        = string
  default     = "francecentral"

  validation {
    condition     = contains(keys(local.region_codes), var.location)
    error_message = "Région non référencée dans local.region_codes."
  }
}

variable "environment" {
  description = "Code d'environnement intégré aux noms (prd, dev)."
  type        = string
  default     = "prd"

  validation {
    condition     = contains(["prd", "dev"], var.environment)
    error_message = "environment doit valoir prd ou dev."
  }
}

variable "owner" {
  description = "Propriétaire des ressources, porté par le tag owner (imposé par policy en couche 1)."
  type        = string
}

variable "operator_object_id" {
  description = "Object ID Entra de l'opérateur humain autorisé à lire/écrire le state du bootstrap."
  type        = string
}

variable "platform_subscription_ids" {
  description = "Subscriptions de la plateforme (hors celle du state), où l'identité plan lit les clusters AKS."
  type        = list(string)
  default     = []
}

variable "manage_github" {
  description = "Gère l'environnement et les secrets GitHub. false par défaut : ils sont gérés à la main (le bootstrap n'a jamais été appliqué avec true) ; true exige un jeton GitHub administrateur du dépôt."
  type        = bool
  default     = false
}

variable "github_owner" {
  description = "Propriétaire GitHub du dépôt, et approbateur de l'environnement protégé."
  type        = string
  default     = "kjourdan1"
}

variable "github_owner_id" {
  description = "ID numérique immuable du propriétaire GitHub, présent dans le sub OIDC."
  type        = number
  default     = 97712877
}

variable "github_repository_id" {
  description = "ID numérique immuable du dépôt GitHub, présent dans le sub OIDC."
  type        = number
  default     = 1325008901
}

variable "github_repository" {
  description = "Dépôt autorisé à obtenir un jeton Azure via OIDC."
  type        = string
  default     = "azure-platform"
}

variable "github_environment" {
  description = "Environnement GitHub protégé dont les jobs obtiennent l'identité apply."
  type        = string
  default     = "prd"
}

variable "cost_center" {
  description = "Centre de coût, porté par le tag cost-center (imposé par policy en couche 1)."
  type        = string
  default     = "azure-platform"
}

# Scope MCA (invoice section) des subscriptions vendues, déjà utilisé par la landing zone :
# le profil de facturation du budget global en est déduit.
variable "subscription_billing_scope" {
  description = "Billing scope MCA (invoice section)."
  type        = string
  sensitive   = true
}

variable "budget_alert_email" {
  description = "E-mail de notification des alertes de budget et d'anomalie."
  type        = string
  sensitive   = true
}

variable "global_budget_amount" {
  description = "Budget mensuel global (toutes subscriptions), en devise de facturation."
  type        = number
  default     = 50
}

variable "budget_start_date" {
  description = "Début du budget global : premier jour d'un mois, format RFC 3339."
  type        = string
  default     = "2026-10-01T00:00:00Z"
}

variable "budget_end_date" {
  description = "Fin du budget global et des alertes d'anomalie, format RFC 3339."
  type        = string
  default     = "2027-12-31T23:59:59Z"
}

variable "anomaly_alert_start_date" {
  description = "Début de l'alerte d'anomalie de coût de la subscription du state, format RFC 3339."
  type        = string
  default     = "2026-11-01T00:00:00Z"
}

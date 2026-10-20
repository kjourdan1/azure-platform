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

variable "manage_github" {
  description = "Gère l'environnement et les variables GitHub. false si l'API GitHub n'est pas joignable avec des droits admin."
  type        = bool
  default     = true
}

variable "github_owner" {
  description = "Propriétaire GitHub du dépôt, et approbateur de l'environnement protégé."
  type        = string
  default     = "kjourdan1"
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

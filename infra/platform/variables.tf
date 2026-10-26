variable "location" {
  description = "Région des ressources de la plateforme."
  type        = string
  default     = "francecentral"
}

variable "environment" {
  description = "Code d'environnement intégré aux noms."
  type        = string
  default     = "prd"
}

variable "hub_address_space" {
  description = "Plage du VNet hub. Les spokes prennent les plages suivantes (10.1.0.0/16 pour AKS)."
  type        = string
  default     = "10.0.0.0/22"
}

variable "log_analytics_daily_quota_gb" {
  description = "Plafond d'ingestion journalier : au-delà, la collecte s'arrête jusqu'au lendemain."
  type        = number
  default     = 0.5
}

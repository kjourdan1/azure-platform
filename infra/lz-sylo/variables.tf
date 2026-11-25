variable "location" {
  description = "Région Azure des ressources."
  type        = string
  default     = "francecentral"
}

variable "environment" {
  description = "Code d'environnement intégré aux noms."
  type        = string
  default     = "prd"
}

variable "address_space" {
  description = "Plage du VNet spoke de Sylo. Sans appairage au hub tant que la stack platform n'est pas appliquée dans le tenant Sylo."
  type        = string
  default     = "10.50.0.0/24"
}

variable "pg_location" {
  description = "Région du serveur PostgreSQL et de son VNet : B1ms est refusé en France Central pour cette subscription."
  type        = string
  default     = "northeurope"
}

variable "pg_address_space" {
  description = "Plage du VNet PostgreSQL en northeurope, distincte du VNet France Central (appairage)."
  type        = string
  default     = "10.51.0.0/24"
}

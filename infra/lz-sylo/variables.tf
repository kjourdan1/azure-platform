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

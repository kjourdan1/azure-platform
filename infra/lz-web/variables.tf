variable "location" {
  description = "Région du resource group. Celle de la Static Web App reste celle de sa création (West Europe) : un déplacement ne change pas de région."
  type        = string
  default     = "francecentral"
}

variable "environment" {
  description = "Code d'environnement intégré aux noms."
  type        = string
  default     = "prd"
}

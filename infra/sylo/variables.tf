variable "environment" {
  description = "Code d'environnement intégré aux noms."
  type        = string
  default     = "prd"
}

variable "placeholder_image" {
  description = "Image de démarrage des Container Apps, utilisée tant que le tag de l'image applicative est vide."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

# Tag des images construites par la CI du dépôt sylo et poussées dans l'ACR. Vide : image de
# démarrage. Déployer une version = changer ce tag dans une PR.
variable "api_image_tag" {
  description = "Tag de l'image sylo-api dans l'ACR (vide : image de démarrage)."
  type        = string
  default     = ""
}

variable "web_image_tag" {
  description = "Tag de l'image sylo-cockpit dans l'ACR (vide : image de démarrage)."
  type        = string
  default     = ""
}

# Identifiants non secrets des applications Entra créées à la main (portail).
variable "entra_api_client_id" {
  description = "Client ID de l'application Entra sylo-api (ENTRA_API_CLIENT_ID de l'API)."
  type        = string
  default     = ""
}

variable "entra_api_audience" {
  description = "URI d'application de sylo-api : audience des jetons et ressource demandée par le cockpit."
  type        = string
  default     = "api://sylo-api"
}

variable "entra_web_client_id" {
  description = "Client ID de l'application Entra sylo-web (authentification intégrée du cockpit). Vide : pas d'authentification intégrée."
  type        = string
  default     = ""
}
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
  default     = "34aac478ae8d"
}

variable "web_image_tag" {
  description = "Tag de l'image sylo-cockpit dans l'ACR (vide : image de démarrage)."
  type        = string
  default     = "34aac478ae8d"
}

# Identifiants non secrets des applications Entra créées à la main (portail).
variable "entra_api_client_id" {
  description = "Client ID de l'application Entra sylo-api (ENTRA_API_CLIENT_ID de l'API)."
  type        = string
  default     = "87a494c0-f9bc-4801-86d0-048805513bb0"
}

variable "entra_api_audience" {
  description = "URI d'application de sylo-api : audience des jetons et ressource demandée par le cockpit."
  type        = string
  default     = "api://87a494c0-f9bc-4801-86d0-048805513bb0" # api://sylo-api refusé par Entra
}

variable "entra_web_client_id" {
  description = "Client ID de l'application Entra sylo-web (authentification intégrée du cockpit). Vide : pas d'authentification intégrée."
  type        = string
  default     = "54cee335-ec73-4817-957a-c25ab1b1d6b3"
}
# n8n (ADR-027) : image publique épinglée, pas construite par la CI. Vide : image de démarrage.
variable "n8n_image_tag" {
  description = "Tag de l'image docker.n8n.io/n8nio/n8n (vide : image de démarrage, n8n non déployé)."
  type        = string
  default     = ""
}

variable "entra_n8n_client_id" {
  description = "Client ID de l'application Entra sylo-n8n-web (authentification intégrée de l'interface n8n). Vide : l'interface n8n reste interne à l'environnement (pas d'ingress externe)."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Code d'environnement intégré aux noms."
  type        = string
  default     = "prd"
}

variable "placeholder_image" {
  description = "Image de démarrage des Container Apps. La CI applicative (Azure DevOps) publie ensuite les vraies révisions ; Terraform ignore l'image (ADR-011)."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

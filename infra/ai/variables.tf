variable "location" {
  description = "Région du compte Foundry. France Central : le déploiement Data Zone garde le traitement dans l'UE."
  type        = string
  default     = "francecentral"
}

variable "environment" {
  description = "Code d'environnement intégré aux noms."
  type        = string
  default     = "prd"
}

variable "operator_object_id" {
  description = "Object ID Entra de l'opérateur humain, utilisateur du projet Foundry."
  type        = string
}

variable "chat_model" {
  description = "Modèle de conversation déployé : nom et version épinglée (pas de mise à jour automatique)."
  type = object({
    name    = string
    version = string
  })
  default = {
    name    = "gpt-5.4-mini"
    version = "2026-03-17" # retrait annoncé le 2027-09-21
  }
}

variable "chat_capacity" {
  description = "Plafond du déploiement, en milliers de tokens par minute. Borne la facture : c'est un plafond, pas une réservation (aucun coût fixe)."
  type        = number
  default     = 10
}

variable "location" {
  description = "Région du cluster."
  type        = string
  default     = "francecentral"
}

variable "environment" {
  description = "Code d'environnement intégré aux noms."
  type        = string
  default     = "prd"
}

variable "system_node_vm_size" {
  description = "Taille des nœuds système : B2s (2 vCPU, 4 Go), minimum supporté pour un pool système."
  type        = string
  default     = "Standard_B2s"
}

variable "system_node_count" {
  description = "Nombre de nœuds du pool système."
  type        = number
  default     = 1
}

variable "operator_object_id" {
  description = "Object ID Entra de l'opérateur humain, administrateur du cluster via Azure RBAC."
  type        = string
}

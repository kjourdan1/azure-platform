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
  description = "Taille des nœuds : B4s_v2 (4 vCPU, 16 Go). Un B2s (4 Go) ne tient pas Flux, les contrôleurs de la plateforme, Prometheus et l'application ; AKS ne propose pas les B-series v1 (B4ms) dans cette subscription en France Central."
  type        = string
  default     = "Standard_B4s_v2"
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

variable "gitops_repository_url" {
  description = "Dépôt lu par Flux. Public : lecture anonyme, aucun credential."
  type        = string
  default     = "https://github.com/kjourdan1/azure-platform"
}

variable "gitops_branch" {
  description = "Branche suivie par Flux."
  type        = string
  default     = "main"
}

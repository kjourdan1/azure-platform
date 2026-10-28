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
  description = "Taille des nœuds : D4as_v7 (4 vCPU, 16 Go). Doit être à la fois autorisée par la policy FinOps, proposée par AKS dans la région et couverte par un quota de vCPU de la subscription (voir infra/aks/README.md)."
  type        = string
  default     = "Standard_D4as_v7"
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

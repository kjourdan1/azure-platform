variable "location" {
  description = "Région des ressources du spoke AKS."
  type        = string
  default     = "francecentral"
}

variable "environment" {
  description = "Code d'environnement intégré aux noms."
  type        = string
  default     = "prd"
}

variable "spoke_address_space" {
  description = "Plage du VNet spoke AKS (le hub occupe 10.0.0.0/22)."
  type        = string
  default     = "10.1.0.0/16"
}

variable "aks_nodes_subnet_prefix" {
  description = "Subnet des nœuds AKS : /22 pour Azure CNI Overlay (les pods n'y consomment pas d'IP)."
  type        = string
  default     = "10.1.0.0/22"
}

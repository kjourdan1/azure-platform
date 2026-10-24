variable "location" {
  description = "Région des identités managées créées pour les policies DeployIfNotExists."
  type        = string
  default     = "francecentral"
}

variable "security_contact_email" {
  description = "Contact Defender for Cloud, porté par la policy Deploy-MDFC-Config."
  type        = string
  default     = "security@azure-platform.invalid"
}

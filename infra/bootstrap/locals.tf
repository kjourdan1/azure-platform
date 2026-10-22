locals {
  project = "azpl"

  region_codes = {
    francecentral = "frc"
    westeurope    = "euw"
  }
  region_code = local.region_codes[var.location]

  # Convention : {type}-{projet}-{composant}-{env}-{region}-{id}
  # Les Storage Accounts n'acceptent ni tiret ni majuscule, 24 caractères max.
  names = {
    resource_group          = "rg-${local.project}-tfstate-${var.environment}-${local.region_code}-001"
    resource_group_identity = "rg-${local.project}-identity-${var.environment}-${local.region_code}-001"
    storage_account         = "st${local.project}tfstate${var.environment}${local.region_code}001"
  }

  tags = {
    owner         = var.owner
    "cost-center" = var.cost_center
    environment   = var.environment
    project       = local.project
    "managed-by"  = "terraform"
    component     = "bootstrap"
  }
}

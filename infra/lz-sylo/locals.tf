locals {
  project     = "azpl"
  region_code = "frc"
  suffix      = "${var.environment}-${local.region_code}-001"
  # PostgreSQL en northeurope (code CAF neu) : voir main.tf.
  pg_suffix = "${var.environment}-neu-001"

  # Convention : {type}-{projet}-{composant}-{env}-{region}-{id} ; composant = sylo.
  names = {
    resource_group = "rg-${local.project}-sylo-${local.suffix}"
    vnet           = "vnet-${local.project}-sylo-${local.suffix}"
    law            = "log-${local.project}-sylo-${local.suffix}"
    key_vault      = "kv-${local.project}-sylo-${local.suffix}"
    # Container Registry : alphanumérique uniquement, 50 caractères max.
    registry = "acr${local.project}sylo${var.environment}${local.region_code}001"
  }

  tags = {
    owner         = "kjourdan1"
    "cost-center" = "sylo"
    environment   = var.environment
    project       = local.project
    "managed-by"  = "terraform"
    component     = "lz-sylo"
  }

  # Une identité managée par charge : droits minimaux (ADR-010, aucun secret dans le code).
  workloads = toset(["api", "web", "n8n"])
}

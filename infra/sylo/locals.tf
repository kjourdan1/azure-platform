locals {
  project     = "azpl"
  region_code = "frc"
  suffix      = "${var.environment}-${local.region_code}-001"

  lz = data.terraform_remote_state.lz_sylo.outputs

  names = {
    environment = "cae-${local.project}-sylo-${local.suffix}"
    postgres    = "psql-${local.project}-sylo-${local.suffix}"
    # Storage Account : alphanumérique, 24 caractères max.
    storage = "st${local.project}sylo${var.environment}${local.region_code}001"
  }

  tags = {
    owner         = "kjourdan1"
    "cost-center" = "sylo"
    environment   = var.environment
    project       = local.project
    "managed-by"  = "terraform"
    component     = "sylo"
  }

  # Charges applicatives (ADR-010, ADR-027). minReplicas = 0 pour web et api (démarrage à froid
  # accepté, NFR-004) ; n8n garde un réplica permanent (routines déterministes).
  apps = {
    api = {
      name         = "ca-sylo-api"
      min_replicas = 0
      max_replicas = 2
      cpu          = 0.5
      memory       = "1Gi"
    }
    web = {
      name         = "ca-sylo-web"
      min_replicas = 0
      max_replicas = 2
      cpu          = 0.5
      memory       = "1Gi"
    }
    n8n = {
      name         = "ca-sylo-n8n"
      min_replicas = 1
      max_replicas = 1
      cpu          = 0.5
      memory       = "1Gi"
    }
  }
}

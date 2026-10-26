locals {
  project     = "azpl"
  region_code = "frc"
  suffix      = "${var.environment}-${local.region_code}-001"

  lz_aks = data.terraform_remote_state.lz_aks.outputs

  tags = {
    owner         = "kjourdan1"
    "cost-center" = "azure-platform"
    environment   = var.environment
    project       = local.project
    "managed-by"  = "terraform"
    component     = "aks"
  }
}

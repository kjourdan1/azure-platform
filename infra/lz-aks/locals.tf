locals {
  project     = "azpl"
  region_code = "frc"
  suffix      = "${var.environment}-${local.region_code}-001"

  hub = data.terraform_remote_state.platform.outputs.hub_virtual_network

  tags = {
    owner         = "kjourdan1"
    "cost-center" = "azure-platform"
    environment   = var.environment
    project       = local.project
    "managed-by"  = "terraform"
    component     = "lz-aks"
  }
}

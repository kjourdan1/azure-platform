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

locals {
  # Valeurs propres à l'environnement, injectées dans gitops/ par post-build substitution
  # (${VAR} dans les manifests) : aucun identifiant dans Git. Marquées sensibles pour ne
  # jamais apparaître en clair dans le plan publié sur les PR (dépôt public).
  flux_substitutions = sensitive({
    AZURE_TENANT_ID        = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID  = local.lz_aks.subscription_id
    DNS_ZONE               = local.lz_aks.dns_zone.name
    DNS_RESOURCE_GROUP     = local.lz_aks.dns_zone.resource_group_name
    KEY_VAULT_URL          = local.lz_aks.key_vault_uri
    ESO_CLIENT_ID          = local.lz_aks.workload_identities.external_secrets.client_id
    EXTERNAL_DNS_CLIENT_ID = local.lz_aks.workload_identities.external_dns.client_id
  })

  # Compte de service Kubernetes autorisé à utiliser chaque identité (namespace:nom).
  workload_identity_subjects = {
    external_secrets = "external-secrets:external-secrets"
    external_dns     = "external-dns:external-dns"
  }
}

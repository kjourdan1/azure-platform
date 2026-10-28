# Credentials fédérés des identités de lz-aks : Entra accepte le jeton d'un compte de service
# du cluster parce qu'il vient de cet émetteur OIDC et porte ce sujet. L'URL de l'émetteur
# change à chaque création de cluster, d'où leur place ici et non dans lz-aks.
resource "azurerm_federated_identity_credential" "workload" {
  for_each = local.workload_identity_subjects

  name                      = "aks-${replace(each.key, "_", "-")}"
  user_assigned_identity_id = local.lz_aks.workload_identities[each.key].id
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "system:serviceaccount:${each.value}"
}

# Flux en extension AKS gérée par Microsoft plutôt que `flux bootstrap` : le bootstrap
# exige un jeton GitHub en écriture stocké quelque part ; ici le dépôt public est lu sans
# credential et Flux arrive avec le cluster, dans le même apply de lab-up.
resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.main.id
  extension_type = "microsoft.flux"
}

# Trois niveaux réconciliés dans l'ordre : les contrôleurs installent leurs CRD, les
# configurations les utilisent (ClusterIssuer, ClusterSecretStore…), puis les applications.
# `wait` attend que chaque niveau soit sain avant de débloquer le suivant.
resource "azurerm_kubernetes_flux_configuration" "platform" {
  name       = "platform"
  cluster_id = azurerm_kubernetes_cluster.main.id
  namespace  = "flux-system"
  scope      = "cluster"

  git_repository {
    url             = var.gitops_repository_url
    reference_type  = "branch"
    reference_value = var.gitops_branch
  }

  kustomizations {
    name                       = "infra-controllers"
    path                       = "./gitops/infrastructure/controllers"
    wait                       = true
    garbage_collection_enabled = true

    post_build {
      substitute = local.flux_substitutions
    }
  }

  kustomizations {
    name                       = "infra-configs"
    path                       = "./gitops/infrastructure/configs"
    depends_on                 = ["infra-controllers"]
    wait                       = true
    garbage_collection_enabled = true

    post_build {
      substitute = local.flux_substitutions
    }
  }

  kustomizations {
    name                       = "apps"
    path                       = "./gitops/apps"
    depends_on                 = ["infra-configs"]
    wait                       = true
    garbage_collection_enabled = true

    post_build {
      substitute = local.flux_substitutions
    }
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}

data "azurerm_client_config" "current" {}

# Resource group propre au cluster, isolé du réseau, du Key Vault et de l'ACR (couche lz-aks,
# permanente). lab-down supprime le cluster chaque soir ; le resource group vide reste.
resource "azurerm_resource_group" "cluster" {
  name     = "rg-${local.project}-aks-cluster-${local.suffix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_kubernetes_cluster" "main" {
  #checkov:skip=CKV_AZURE_115:Cluster public : un cluster privé exige un runner dans le VNet ; API protégée par Entra et comptes locaux désactivés
  #checkov:skip=CKV_AZURE_6:Plages IP autorisées impossibles avec des runners hébergés à IP dynamiques ; cible : runner self-hosted
  #checkov:skip=CKV_AZURE_117:Disk encryption set (CMK) : Key Vault et coût supplémentaires, chiffrement Microsoft par défaut
  #checkov:skip=CKV_AZURE_227:Chiffrement hôte : fonctionnalité à activer sur la subscription, hors périmètre lab
  #checkov:skip=CKV_AZURE_226:Disque OS éphémère : le cache des B2s est trop petit
  #checkov:skip=CKV_AZURE_170:Tier Free du plan de contrôle (sans SLA) : budget de lab
  #checkov:skip=CKV_AZURE_4:Container Insights (Log Analytics) : ingestion payante ; observabilité par kube-prometheus-stack
  #checkov:skip=CKV_AZURE_172:CSI Secrets Store non utilisé : les secrets passent par External Secrets Operator
  #checkov:skip=CKV_AZURE_232:Pool unique pour le lab : système et applications partagent les nœuds
  name                = "aks-${local.project}-${local.suffix}"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = azurerm_resource_group.cluster.location
  dns_prefix          = "aks-${local.project}-${var.environment}"
  sku_tier            = "Free"

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Identités sans secret : OIDC + Workload Identity pour les pods (External Secrets),
  # Entra ID + Azure RBAC pour les humains, aucun compte local.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  local_account_disabled    = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  # KEDA en add-on géré par AKS : scaling sur des événements (longueur d'une file RabbitMQ)
  # plutôt que sur le CPU, sans chart à maintenir.
  workload_autoscaler_profile {
    keda_enabled = true
  }

  # Gouvernance dans le cluster : les policies AKS de la landing zone (privilèges,
  # HTTPS) s'appliquent via l'add-on Azure Policy.
  azure_policy_enabled = true

  identity {
    type = "SystemAssigned"
  }

  # Pools gérés explicitement en Terraform (pas de Node Auto Provisioning) : le pool GPU
  # de la couche IA sera un pool dédié, créé et détruit à la demande.
  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name                        = "system"
    vm_size                     = var.system_node_vm_size
    node_count                  = var.system_node_count
    vnet_subnet_id              = local.lz_aks.aks_nodes_subnet_id
    os_disk_type                = "Managed"
    os_disk_size_gb             = 30
    max_pods                    = 110
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Azure CNI Overlay + Cilium : les pods ne consomment pas d'IP du VNet, politiques
  # réseau eBPF sans composant supplémentaire.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  tags = local.tags
}

# Pull des images sans secret : l'identité kubelet reçoit AcrPull sur le registre.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = local.lz_aks.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.operator_object_id
}

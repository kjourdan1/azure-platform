locals {
  alz_root_id = module.alz.management_group_resource_ids["alz"]

  # Tailles de VM autorisées dans toute la hiérarchie, nœuds AKS compris (la policy couvre
  # aussi les scale sets). Aucune taille GPU : la couche IA ajoutera une exemption ciblée
  # sur son resource group, avec quota et budget dédiés.
  allowed_vm_skus = [
    "Standard_B1s", "Standard_B1ms", "Standard_B2s", "Standard_B2ms", "Standard_B4ms",
    "Standard_B2s_v2", "Standard_B2ls_v2", "Standard_B4s_v2", "Standard_B4ls_v2",
    "Standard_D2s_v5", "Standard_D4s_v5", "Standard_D2as_v5", "Standard_D4as_v5",
    "Standard_D2ads_v5", "Standard_D4ads_v5",
  ]

  # Ressources à coût fixe élevé, facturées à l'heure même sans trafic. Elles restent
  # au stade du plan : un apply échoue, c'est voulu.
  denied_resource_types = [
    "Microsoft.Network/azureFirewalls",
    "Microsoft.Network/bastionHosts",
    "Microsoft.Network/virtualNetworkGateways",
    "Microsoft.Network/vpnGateways",
    "Microsoft.Network/expressRouteCircuits",
    "Microsoft.Network/expressRouteGateways",
    "Microsoft.Network/applicationGateways",
    "Microsoft.Network/ddosProtectionPlans",
    "Microsoft.Network/natGateways",
    "Microsoft.Network/virtualHubs",
    "Microsoft.Network/dnsResolvers",
  ]

  # Tags de répartition des coûts : imposés sur les resource groups, hérités par les
  # ressources. Un deny sur les ressources bloquerait celles qu'AKS crée lui-même.
  cost_tags = ["owner", "cost-center"]

  # Définitions intégrées Azure Policy et rôle (IDs stables, documentés par Microsoft).
  builtin = {
    allowed_vm_skus      = "/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3"
    not_allowed_types    = "/providers/Microsoft.Authorization/policyDefinitions/6c112d4e-5bc7-47ae-a041-ea2d9dccd749"
    require_rg_tag       = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
    inherit_tag_from_rg  = "/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070"
    tag_contributor_role = "/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f"
  }
}

resource "azapi_resource" "allowed_vm_skus" {
  type      = "Microsoft.Authorization/policyAssignments@2024-04-01"
  name      = "azpl-allowed-vm-skus"
  parent_id = local.alz_root_id

  body = {
    properties = {
      displayName        = "FinOps - allowed VM sizes (no GPU)"
      policyDefinitionId = local.builtin.allowed_vm_skus
      enforcementMode    = "Default"
      parameters = {
        listOfAllowedSKUs = { value = local.allowed_vm_skus }
      }
      nonComplianceMessages = [{ message = "VM size not in the FinOps allow list (infra/landing-zone/finops.tf)." }]
    }
  }
}

resource "azapi_resource" "denied_resource_types" {
  type      = "Microsoft.Authorization/policyAssignments@2024-04-01"
  name      = "azpl-deny-costly-types"
  parent_id = local.alz_root_id

  body = {
    properties = {
      displayName        = "FinOps - high fixed-cost resource types denied"
      policyDefinitionId = local.builtin.not_allowed_types
      enforcementMode    = "Default"
      parameters = {
        listOfResourceTypesNotAllowed = { value = local.denied_resource_types }
      }
      nonComplianceMessages = [{ message = "Resource type denied by the FinOps policy: keep it at plan stage." }]
    }
  }
}

resource "azapi_resource" "require_rg_tag" {
  for_each = toset(local.cost_tags)

  type      = "Microsoft.Authorization/policyAssignments@2024-04-01"
  name      = "azpl-rg-tag-${each.key}"
  parent_id = local.alz_root_id

  body = {
    properties = {
      displayName        = "FinOps - ${each.key} tag required on resource groups"
      policyDefinitionId = local.builtin.require_rg_tag
      enforcementMode    = "Default"
      parameters = {
        tagName = { value = each.key }
      }
      nonComplianceMessages = [{ message = "Resource group is missing the ${each.key} tag." }]
    }
  }
}

# Modify : complète le tag manquant à la création à partir du resource group. L'identité
# ne sert qu'aux tâches de remédiation de l'existant : Tag Contributor suffit.
resource "azapi_resource" "inherit_tag" {
  for_each = toset(local.cost_tags)

  type      = "Microsoft.Authorization/policyAssignments@2024-04-01"
  name      = "azpl-inh-tag-${each.key}"
  parent_id = local.alz_root_id
  location  = var.location

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      displayName        = "FinOps - ${each.key} tag inherited from resource group"
      policyDefinitionId = local.builtin.inherit_tag_from_rg
      enforcementMode    = "Default"
      parameters = {
        tagName = { value = each.key }
      }
    }
  }
}

resource "azapi_resource" "inherit_tag_role" {
  for_each = toset(local.cost_tags)

  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${local.alz_root_id}/azpl-inh-tag-${each.key}/tag-contributor")
  parent_id = local.alz_root_id

  body = {
    properties = {
      roleDefinitionId = local.builtin.tag_contributor_role
      principalId      = azapi_resource.inherit_tag[each.key].identity[0].principal_id
      principalType    = "ServicePrincipal"
    }
  }
}

# Alerte d'anomalie de coût, gratuite : un écart inhabituel est signalé dès le lendemain,
# là où un budget n'alerte qu'au franchissement d'un seuil.
resource "azapi_resource" "anomaly_alert" {
  for_each = local.subscription_ids

  type      = "Microsoft.CostManagement/scheduledActions@2023-11-01"
  name      = "anomaly-azpl-${replace(each.key, "_", "-")}"
  parent_id = "/subscriptions/${each.value}"

  body = {
    kind = "InsightAlert"
    properties = {
      displayName = "Cost anomaly ${local.subscriptions[each.key].alias_name}"
      status      = "Enabled"
      viewId      = "/subscriptions/${each.value}/providers/Microsoft.CostManagement/views/ms:DailyAnomalyByResourceGroup"
      notification = {
        to      = [var.budget_alert_email]
        subject = "Cost anomaly ${local.subscriptions[each.key].alias_name}"
      }
      schedule = {
        frequency = "Daily"
        startDate = var.anomaly_alert_start_date
        endDate   = var.budget_end_date
      }
    }
  }
}

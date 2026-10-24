data "azapi_client_config" "current" {}

locals {
  # Affectations ALZ qui déploieraient des ressources payantes (agents de monitoring,
  # sauvegardes, Defender) ou qui dépendent de ressources pas encore créées (Log Analytics,
  # DCR, zones DNS privées, plan DDoS). En DoNotEnforce, la conformité reste évaluée et
  # visible, mais rien n'est déployé. On les réactive couche par couche, quand la
  # ressource qu'elles référencent existe.
  cost_guard = {
    alz = [
      "Deploy-AzActivity-Log",
      "Deploy-Diag-LogsCat",
      "Deploy-MDEndpoints",
      "Deploy-MDEndpointsAMA",
      "Deploy-MDFC-Config-H224",
      "Deploy-MDFC-OssDb",
      "Deploy-MDFC-SqlAtp",
    ]
    platform = [
      "Deploy-MDFC-DefSQL-AMA",
      "Deploy-VM-ChangeTrack",
      "Deploy-VM-Monitoring",
      "Deploy-VMSS-ChangeTrack",
      "Deploy-VMSS-Monitoring",
      "Deploy-vmArc-ChangeTrack",
      "Deploy-vmHybr-Monitoring",
    ]
    landingzones = [
      "Deploy-AzSqlDb-Auditing",
      "Deploy-MDFC-DefSQL-AMA",
      "Deploy-SQL-Threat",
      "Deploy-VM-Backup",
      "Deploy-VM-ChangeTrack",
      "Deploy-VM-Monitoring",
      "Deploy-VMSS-ChangeTrack",
      "Deploy-VMSS-Monitoring",
      "Deploy-vmArc-ChangeTrack",
      "Deploy-vmHybr-Monitoring",
      "Enable-DDoS-VNET",
    ]
    connectivity = ["Enable-DDoS-VNET"]
    identity     = ["Deploy-VM-Backup"]
    corp         = ["Deploy-Private-DNS-Zones"]
  }

  policy_assignments_to_modify = {
    for mg, assignments in local.cost_guard : mg => {
      policy_assignments = {
        for name in assignments : name => { enforcement_mode = "DoNotEnforce" }
      }
    }
  }
}

# Hiérarchie de management groups et policies de référence ALZ, sous le Tenant Root Group.
# La subscription du state (LAB) reste à la racine : aucune policy ALZ ne s'y applique.
module "alz" {
  # Épinglé par commit (tag v0.22.0) : le lock file vérifie les providers, pas les modules.
  source = "git::https://github.com/Azure/terraform-azurerm-avm-ptn-alz.git?ref=e2a318c3eba91967c4ce3cd2738b2b2569db994e"

  architecture_name  = "alz"
  location           = var.location
  parent_resource_id = data.azapi_client_config.current.tenant_id
  enable_telemetry   = false

  policy_assignments_to_modify = local.policy_assignments_to_modify

  policy_default_values = {
    email_security_contact = jsonencode({ value = var.security_contact_email })
  }
}

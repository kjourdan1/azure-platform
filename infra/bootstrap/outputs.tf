output "backend_config" {
  description = "Bloc backend à copier dans backend.tf après le premier apply."
  value       = <<-EOT
    terraform {
      backend "azurerm" {
        resource_group_name  = "${azurerm_resource_group.tfstate.name}"
        storage_account_name = "${azurerm_storage_account.tfstate.name}"
        container_name       = "${azurerm_storage_container.tfstate.name}"
        key                  = "bootstrap.tfstate"
        use_azuread_auth     = true
      }
    }
  EOT
}

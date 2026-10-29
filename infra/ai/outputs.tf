output "foundry_endpoint" {
  description = "Endpoint du compte Foundry."
  value       = azurerm_cognitive_account.foundry.endpoint
}

output "chat_deployment" {
  description = "Nom du déploiement de conversation (paramètre model des appels)."
  value       = azurerm_cognitive_deployment.chat.name
}

# À copier dans le secret AZURE_CLIENT_ID_AI_SMOKE de l'environnement GitHub lab.
output "smoke_client_id" {
  description = "Client ID de l'identité du workflow ai-smoke."
  value       = azurerm_user_assigned_identity.smoke.client_id
  sensitive   = true
}

# Lues par les couches suivantes via terraform_remote_state : aucun ID de subscription
# dans le code ni dans un secret supplémentaire. sensitive : les IDs ne sont pas des
# secrets GitHub, le masquage des logs ne les couvrirait pas.
output "subscription_ids" {
  description = "IDs des subscriptions vendues, par clé (platform, lz_aks)."
  value       = { for key, sub in module.subscriptions : key => sub.subscription_id }
  sensitive   = true
}

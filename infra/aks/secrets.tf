# Date d'expiration des secrets que le cluster écrit dans Key Vault (PushSecret d'ESO).
# La policy ALZ Enforce-GR-KeyVault refuse un secret sans expiration ou valide plus de
# 90 jours. Rotation tous les 30 jours + 60 jours de validité : la date injectée reste
# entre 30 et 60 jours dans le futur, et ne change pas à chaque plan.
resource "time_rotating" "secret_expiry" {
  rotation_days = 30
}

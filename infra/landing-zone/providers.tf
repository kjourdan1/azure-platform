# Authentification via les variables ARM_* (OIDC en CI, Azure CLI en local) :
# aucun identifiant de tenant ou de subscription dans le code.
provider "azapi" {}

# Bibliothèque de référence Azure Landing Zones, version figée : une montée de version
# est une PR dont le plan montre les policies ajoutées ou modifiées.
provider "alz" {
  library_references = [
    {
      path = "platform/alz"
      ref  = "2026.10.0"
    }
  ]
}

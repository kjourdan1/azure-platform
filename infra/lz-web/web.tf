# Resource group d'accueil du portfolio (reprise brownfield, docs/runbooks/brownfield-lab.md).
# Il doit exister et être conforme avant le déplacement de la Static Web App depuis LAB ;
# la Static Web App y sera ensuite importée, pas recréée.
resource "azurerm_resource_group" "web" {
  name     = "rg-${local.project}-web-${local.suffix}"
  location = var.location
  tags     = local.tags
}

# Portfolio repris de LAB (déplacé le 2026-10-30, puis importé) : la ressource existante est
# rattachée au code sans recréation. Le plan d'import ne doit modifier que les tags.
# azapi plutôt qu'azurerm : azurerm lit la clé de déploiement du site à chaque refresh
# (listSecrets). Il faudrait ouvrir ce droit à l'identité plan, qui exécute le code des PR,
# et la clé finirait dans le state. azapi décrit la ressource ARM sans lire ses secrets.
import {
  to = azapi_resource.portfolio
  id = "${azurerm_resource_group.web.id}/providers/Microsoft.Web/staticSites/portfolio-kj"
}

resource "azapi_resource" "portfolio" {
  type      = "Microsoft.Web/staticSites@2025-03-01"
  name      = "portfolio-kj"
  parent_id = azurerm_resource_group.web.id
  # Région d'origine conservée : un déplacement ne change pas de région.
  location = "westeurope"

  # Corps identique à l'existant, lien au dépôt compris : azapi envoie le corps complet à
  # chaque mise à jour, en omettre une propriété la supprimerait (le déploiement depuis le
  # dépôt portfolio-kj casserait). Ce sont des métadonnées ; le jeton de déploiement, lui,
  # n'est jamais lu ni écrit ici.
  body = {
    sku = {
      name = "Free"
      tier = "Free"
    }
    properties = {
      provider                 = "GitHub"
      repositoryUrl            = "https://github.com/kjourdan1/portfolio-kj"
      branch                   = "main"
      stagingEnvironmentPolicy = "Enabled"
      allowConfigFileUpdates   = true
      enterpriseGradeCdnStatus = "Disabled"
    }
  }

  # Tags gérés par la ressource tags ci-dessous, sans réécrire le site.
  lifecycle {
    ignore_changes = [tags]
  }
}

# Tags posés par l'API Tags d'ARM : seule la propriété tags change, la ressource n'est pas
# réécrite. La manière la plus sûre de mettre en conformité une ressource reprise.
# azapi_update_resource et non azapi_resource : la sous-ressource tags/default existe
# toujours (vide ou non), on la met à jour, on ne la crée pas.
resource "azapi_update_resource" "portfolio_tags" {
  type        = "Microsoft.Resources/tags@2021-04-01"
  resource_id = "${azapi_resource.portfolio.id}/providers/Microsoft.Resources/tags/default"
  body = {
    properties = {
      tags = local.tags
    }
  }
}

import {
  to = azapi_resource.portfolio_www
  id = "${azurerm_resource_group.web.id}/providers/Microsoft.Web/staticSites/portfolio-kj/customDomains/www.killianjourdan.com"
}

# Domaine en production, validé par CNAME chez IONOS. L'apex killianjourdan.com, en échec
# avant la reprise (il ne résout plus vers le site), n'est pas repris : à corriger ou
# supprimer par une décision séparée.
resource "azapi_resource" "portfolio_www" {
  type      = "Microsoft.Web/staticSites/customDomains@2024-04-01"
  name      = "www.killianjourdan.com"
  parent_id = azapi_resource.portfolio.id
  body = {
    properties = {}
  }
}

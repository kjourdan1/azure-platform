# Landing zone web

## Problème résolu
Le portfolio (`www.killianjourdan.com`) vivait dans `LAB`, la subscription du state Terraform,
hors de toute gouvernance. Cette couche lui donne une landing zone : subscription `azpl-lz-web`
sous le management group `online`, resource group tagué, ressources déclarées en code.

## Approche retenue
Reprise brownfield sans recréation (`docs/runbooks/brownfield-lab.md`) :
1. ce resource group d'accueil, créé et conforme avant le déplacement ;
2. déplacement de la Static Web App existante par l'opérateur (droits sur `LAB` que la CI n'a pas) ;
3. import de la Static Web App et de son domaine dans cette couche par des blocs `import`.

## Décisions et alternatives écartées
- **Déplacer plutôt que recréer** : une recréation changerait le nom d'hôte par défaut et le
  jeton de déploiement, et imposerait de revalider le domaine personnalisé.
- **Subscription dédiée plutôt que `azpl-lz-aks`** : une charge de travail publique distincte,
  avec son budget et son alerte d'anomalie propres.
- **`azapi` plutôt qu'`azurerm` pour la Static Web App** : `azurerm` lit la clé de déploiement
  du site à chaque refresh (`listSecrets`). Il aurait fallu ouvrir ce droit à l'identité `plan`,
  qui exécute le code des PR, et la clé aurait fini dans le state. `azapi` décrit la ressource
  ARM sans lire ses secrets.
- **Corps du site identique à l'existant, lien au dépôt compris** : `azapi` envoie le corps
  complet, une propriété omise serait supprimée (le déploiement depuis `portfolio-kj` casserait).
- **Tags par l'API Tags d'ARM** (`Microsoft.Resources/tags`) : la mise en conformité ne réécrit
  pas la ressource reprise.
- **Apex `killianjourdan.com` non repris** : en échec avant la reprise (il ne résout plus vers le
  site). À corriger côté DNS ou à supprimer, par une décision séparée.
- **Région de la Static Web App inchangée** (West Europe) : un déplacement ne change pas de
  région ; le resource group, lui, est en France Central comme le reste.

## Installation
PR → plan commenté → merge → `apply-lz-web` avec approbation.

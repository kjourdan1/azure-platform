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
- **Région de la Static Web App inchangée** (West Europe) : un déplacement ne change pas de
  région ; le resource group, lui, est en France Central comme le reste.

## Installation
PR → plan commenté → merge → `apply-lz-web` avec approbation.

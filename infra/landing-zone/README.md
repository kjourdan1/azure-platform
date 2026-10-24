# Landing Zone

## Problème résolu
Gouverner le tenant avant d'y déployer quoi que ce soit : hiérarchie de management groups
et policies de référence, appliquées par héritage à toute subscription placée dessous.

## Approche retenue
Module Azure Verified Module `avm-ptn-alz` (architecture `alz`, bibliothèque ALZ figée en
version), déployé sous le Tenant Root Group par le workflow `terraform-apply` après
approbation dans l'environnement `prd`.

## Décisions et alternatives écartées
- **AVM plutôt qu'un module maison** : c'est le standard Microsoft, maintenu au rythme des
  policies. Le module est épinglé par commit Git (le lock file ne couvre pas les modules).
- **Garde-fou de coût** : les affectations qui déploieraient des ressources payantes ou
  dépendantes de ressources absentes (Log Analytics, DCR, DNS privé, DDoS) sont en
  `DoNotEnforce` (`local.cost_guard`). La conformité reste évaluée, rien n'est déployé.
- **Subscription du state hors hiérarchie** : elle reste au Tenant Root Group, aucune policy
  ALZ ne s'y applique.

## Limites connues
- Aucune subscription placée pour l'instant : les policies n'ont encore rien à évaluer.
- Les affectations en `DoNotEnforce` seront réactivées quand la couche management (Log
  Analytics, DCR) existera.

## Installation
Pas d'apply local : PR → plan commenté → merge → `terraform-apply` avec approbation.

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
- **Garde-fous FinOps qui empêchent plutôt qu'ils n'alertent** (`finops.tf`), sur le
  management group `alz` :
  - tailles de VM autorisées (familles B et D v5 jusqu'à 4 vCPU), **aucun GPU** : la couche
    IA ajoutera une exemption ciblée, avec quota et budget dédiés ;
  - types à coût fixe élevé interdits (Firewall, Bastion, passerelles VPN/ExpressRoute,
    Application Gateway, DDoS, NAT Gateway, Virtual WAN, DNS Resolver) : ils restent au
    stade du plan ;
  - tags `owner` et `cost-center` : `deny` sur les resource groups, `modify` (héritage) sur
    les ressources. Un `deny` sur les ressources bloquerait celles qu'AKS crée lui-même ;
    le cluster propage ses tags à son resource group de nœuds.
  - alerte d'anomalie de coût quotidienne par subscription (gratuite).
- **Budget global de 50 €/mois dans le bootstrap** : le profil de facturation est le seul
  scope qui couvre tout, LAB comprise, et il exige un rôle de facturation que la CI n'a pas.
- **Subscription du state hors hiérarchie** : elle reste au Tenant Root Group, aucune policy
  ALZ ne s'y applique.

## Limites connues
- Subscriptions créées par alias (compte MCA) : l'identité apply doit détenir le rôle de
  facturation « Azure subscription creator » sur l'invoice section. MCA n'autorise qu'une
  création par 24 h : en ajouter deux fait échouer la seconde en `429`, à relancer le lendemain.
- **L'alias ne vit que le temps de la création.** Azure exige le droit d'écriture sur un alias
  pour simplement le lire, ce qui casserait le plan des PR (identité en lecture seule). Les
  subscriptions sont gérées par leur ID, retrouvé par leur nom ; l'alias est retiré du state
  par un bloc `removed`, sans appel à Azure. Créer une nouvelle subscription : réintroduire
  temporairement la ressource `subscription_alias` (commit `e61e625`) et la variable du
  billing scope, puis la retirer de la même façon.
- **Pas d'alias dans le module de vending** : le désactiver après coup détruirait son action
  `subscription_cancel`, qui annule la subscription. Le module ne gère que l'existant.
- Budgets par subscription : Cost Management ne supporte pas les management groups en MCA.
  Le budget global (bootstrap) couvre l'ensemble au niveau du profil de facturation.
- Un budget ou une alerte d'anomalie ne bloque rien et arrive avec 8 à 24 h de retard : la
  protection réelle vient des policies `deny`, du quota et de `lab-down`.
- Les affectations en `DoNotEnforce` seront réactivées quand la couche management (Log
  Analytics, DCR) existera.

## Installation
Pas d'apply local : PR → plan commenté → merge → `terraform-apply` avec approbation.

# Platform

## Problème résolu
Fournir les services partagés dont dépendent les workloads : un workspace Log Analytics
central et un VNet hub auquel les spokes se raccordent.

## Approche retenue
Couche Terraform dédiée dans la subscription `azpl-platform`, dont l'ID est lu dans le
state de la landing zone (subscription vending) : aucun ID dans le code.

## Décisions et alternatives écartées
- **Hub sans Azure Firewall, Bastion ni VPN Gateway** : plusieurs centaines d'euros par mois,
  hors budget. Ils restent au stade plan ; le hub porte le peering et le DNS privé à venir.
- **Log Analytics plafonné** (`daily_quota_gb`) avec 30 jours de rétention, inclus dans le
  prix : la facture fantôme d'un workspace oublié est bornée.
- **Ressources permanentes** : quasi gratuites (le VNet l'est, Log Analytics ne facture que
  l'ingestion), elles ne sont pas détruites par `lab-down`.

## Limites connues
- Pas d'inspection du trafic est-ouest ni de sortie centralisée sans pare-feu.

## Installation
PR → plan commenté → merge → `apply-platform` avec approbation.

# Landing zone AKS

## Problème résolu
Préparer tout ce dont le cluster a besoin et qui doit survivre à sa destruction nocturne :
réseau raccordé au hub, coffre de secrets, registre d'images.

## Approche retenue
Couche dans la subscription `azpl-lz-aks` (management group `online`). Le cluster vivra
dans son propre resource group, créé et détruit à la demande ; ces ressources-ci restent.

## Décisions et alternatives écartées
- **Subnet créé avec son NSG** (`network_security_group_id_wo`) : la policy ALZ
  `Deny-Subnet-Without-Nsg` refuse une association faite après coup.
- **Peering bidirectionnel multi-subscription** : alias de provider explicite pour le côté hub.
- **Key Vault conforme aux deny ALZ** (RBAC, soft delete, purge protection), permanent : la
  purge protection réserve le nom pendant la rétention, il ne peut pas suivre `lab-down`.
  Les secrets devront porter un `content_type` et une expiration (`Enforce-GR-KeyVault`).
- **ACR Basic (~5 €/mois)** plutôt que Premium (~45 €/mois) : les contrôles checkov réservés
  au Premium sont ignorés avec justification.
- **Identité `lab-down` dédiée** (`lab.tf`) : rôle personnalisé limité à lire et supprimer
  les clusters AKS de la subscription, fédéré au seul environnement GitHub `lab`. Elle tourne
  sans approbation, donc elle ne peut rien faire d'autre. Pas de suppression de resource
  group : le réseau, le coffre et le registre sont hors de portée par construction.
- **Port 80 ouvert vers l'ingress** : redirection HTTPS et challenge ACME HTTP-01.

## Limites connues
- Key Vault et ACR exposés publiquement (accès Entra uniquement) tant que les runners sont
  hébergés par GitHub : private endpoints prévus avec un runner self-hosted.

## Installation
PR → plan commenté → merge → `terraform-apply` avec approbation.
Puis copier `terraform output -raw lab_client_id` dans le secret `AZURE_CLIENT_ID_LAB` de
l'environnement GitHub `lab` (branche `main` uniquement, sans reviewer).

# Landing zone AKS

## Problème résolu
Préparer tout ce dont le cluster a besoin et qui doit survivre à sa destruction nocturne :
réseau raccordé au hub, coffre de secrets, registre d'images, sous-zone DNS publique et
identités des contrôleurs du cluster qui parlent à Azure.

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
- **Sous-zone Azure DNS `lab.killianjourdan.com`** (≈ 0,50 €/mois) plutôt que l'API IONOS :
  une clé API IONOS donne accès à tout le compte et devrait être stockée. Seul l'hôte `lab`
  est délégué ; le portfolio reste chez IONOS. Zone permanente (`prevent_destroy`) : la
  recréer changerait ses serveurs de noms et casserait la délégation.
- **Identités des contrôleurs** (`workload-identities.tf`), permanentes avec leurs rôles :
  `external-dns` en *DNS Zone Contributor* sur la seule sous-zone, `external-secrets` en
  *Key Vault Secrets Officer* sur le coffre. Officer et non User : ESO crée lui-même les
  mots de passe absents puis les relit, ce qui les garde hors du state Terraform (sinon
  l'identité `plan`, qui exécute le code des PR, devrait pouvoir les lire). Leurs
  credentials fédérés vivent dans `infra/aks`, car l'émetteur OIDC change à chaque cluster.

## Limites connues
- Key Vault et ACR exposés publiquement (accès Entra uniquement) tant que les runners sont
  hébergés par GitHub : private endpoints prévus avec un runner self-hosted.

## Installation
PR → plan commenté → merge → `apply-lz-aks` avec approbation.
Puis copier `terraform output -raw lab_client_id` dans le secret `AZURE_CLIENT_ID_LAB` de
l'environnement GitHub `lab` (branche `main` uniquement, sans reviewer).

Délégation DNS, une seule fois après le premier apply :
1. `az network dns zone show -g rg-azpl-aks-shared-prd-frc-001 -n lab.killianjourdan.com --query nameServers -o tsv`
   (ou `terraform output dns_zone_name_servers`).
2. Chez IONOS, dans la zone `killianjourdan.com`, créer 4 enregistrements **NS** d'hôte
   `lab`, un par serveur (sans le point final).
3. Vérifier : `dig +short NS lab.killianjourdan.com` renvoie les 4 serveurs `azure-dns`.

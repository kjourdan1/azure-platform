# Intégrer l'AI Landing Zone d'Azure : plan

**Objectif :** reprendre les éléments de l'architecture de référence
[Azure/AI-Landing-Zones](https://github.com/Azure/AI-Landing-Zones) (mode *with platform
hub*) sans sortir du budget de 50 €/mois et en gardant `lab-up` / `lab-down`.

Statut : plan. Rien n'est écrit ni déployé.

## Lecture de la référence

| Volet | Contenu | Position |
|---|---|---|
| Agent Landing Zone | Foundry, Container Apps, AI Search, Cosmos DB, App Configuration, Key Vault, réseau privé (private endpoints, firewall, Bastion, jumpbox, NAT) ; déployé par `azd` | Repris par morceaux : le déploiement tel quel coûte plusieurs centaines d'euros par mois et passe par `azd`, pas par une stack et un pipeline par couche |
| AI Gateway Landing Zone (« Citadel ») | APIM en passerelle IA : quotas de tokens, imputation des coûts par équipe, usage vers Event Hub et Cosmos DB | Même rôle tenu dans le cluster ; APIM documenté comme cible |
| Checklist de conception | Évaluation d'un environnement existant, domaine par domaine | Reprise telle quelle pour l'analyse d'écart |

Ce que la référence confirme pour le firewall : SKU Basic par défaut, subnet
`AzureFirewallManagementSubnet` en /26 au moins avec une IP publique dédiée, pas de DNS proxy
en Basic, règles applicatives par FQDN et règles réseau par IP ou service tag, flux sortants
déclarés par composant.

## Principe : trois niveaux de cycle de vie

Chaque brique est classée selon son coût fixe, son temps de création et l'état qu'elle porte.

| Niveau | Règle | Briques |
|---|---|---|
| 0. Permanent, gratuit ou presque | Tout ce qui définit la structure et les règles | Subnets du hub, route tables, **Firewall Policy, règles, IP Groups**, zones DNS privées, identités et rôles, Foundry (au token), Key Vault ; niveaux gratuits des services de données |
| 1. Permanent, arrêtable | Créé une fois, payé seulement en marche | Azure Firewall en allocation / désallocation (option B ci-dessous) |
| 2. Éphémère | Créé par `lab-up`, détruit par `lab-down` | Cluster AKS et ses charges, instance du firewall (option A), association de la route par défaut, private endpoint de Foundry |

Conséquence : les règles du firewall s'écrivent, se relisent et s'appliquent par PR à tout
moment, sans firewall allumé et sans coût.

## Temps de création et coût fixe

Les durées sont des ordres de grandeur, à remplacer par les mesures du premier `lab-up`.

| Brique | Création | Coût fixe | Source du prix |
|---|---|---|---|
| VNet, subnets, peering, NSG, route tables, IP Groups, Firewall Policy et règles | secondes | 0 | Policy gratuite tant qu'elle n'est associée qu'à un firewall |
| Private endpoint, zone DNS privée | 1 à 2 min | faible | à vérifier |
| Azure Firewall Basic | 5 à 15 min, à mesurer | 0,3546 €/h + 0,0584 €/Go | API Retail Prices, France Central |
| IP publique Standard (2 pour le firewall Basic) | secondes | 0,0045 €/h chacune | API Retail Prices |
| AKS (1 nœud D4as_v7) | 5 à 10 min | 0,1912 €/h | API Retail Prices |
| APIM Developer ou Premium classique | 30 à 60 min | élevé, sans arrêt possible | à chiffrer |
| APIM Consumption | minutes | à l'appel | à chiffrer |
| Passerelle VPN ou ExpressRoute | 30 à 45 min | élevé | hors périmètre |

## Firewall : deux options

| | A. Créer et détruire | B. Allouer et désallouer |
|---|---|---|
| Mécanisme | Stack `infra/lab-network` appliquée par `lab-up` avant `infra/aks`, détruite par `lab-down` | Firewall créé une fois ; `lab-up` l'alloue, `lab-down` le désalloue |
| Coût lab éteint | 0 | 2 IP publiques, environ 6,5 €/mois |
| Durée de `lab-up` | Attend la création | Plus courte, à mesurer |
| Terraform | Pur, lisible | Une partie de l'état sort de Terraform |

**Choix : A**, avec mesure du temps réel. Passage à B seulement si l'attente gêne.

Ordre imposé à la montée : firewall, route `0.0.0.0/0`, puis AKS en
`outboundType = userDefinedRouting`. À la descente : AKS d'abord, firewall ensuite.

## Règles du firewall

```
infra/connectivity/rules/
  platform.yaml   # socle du hub : prérequis AKS (FQDN tag), NTP, Azure Monitor (priorités 100 à 999)
  lz-aks.yaml     # spoke AKS (priorités 1000 à 1999)
  # un fichier et une plage de priorités par spoke ou par environnement
```

- Règles en données (YAML lu par Terraform) : ajouter un environnement, c'est ajouter un fichier.
- Un IP Group et une plage de priorités par spoke ; tout ce qui n'est pas autorisé est refusé.
- Garde-fous en CI par `terraform test`, sans accès Azure : priorités uniques et dans la plage
  du spoke, aucune règle « any vers any », aucune destination `*` en règle réseau, description
  obligatoire.
- Le plan de la PR est la revue de flux.

## Passerelle IA

| Option | Coût fixe | Cycle de vie | Remarque |
|---|---|---|---|
| APIM Developer | élevé | permanent | Le plus proche de la référence |
| APIM Consumption | à l'appel | permanent | Pas d'intégration réseau privé ; prise en charge des policies de tokens à vérifier |
| **Envoy AI Gateway sur AKS** | **0** | **suit le lab, déployé par Flux** | S'appuie sur l'Envoy Gateway déjà en place ; limite de débit en tokens |

**Choix : Envoy AI Gateway dans le lab**, APIM documenté comme cible chez un client où il est
permanent dans le hub.

## Étapes

| # | Étape | Niveau | Coût ajouté | Critère de succès |
|---|---|---|---|---|
| 1 | Analyse d'écart contre la checklist (`docs/design/ai-landing-zone-gap.md`) : couvert, manquant, écarté et pourquoi | – | 0 | Chaque domaine de la checklist a un statut et une décision |
| 2 | Hub : subnets, Firewall Policy, IP Groups, règles en YAML, tests des règles | 0 | 0 | Plan sans instance de firewall ; `terraform test` rouge sur une règle interdite |
| 3 | Instance du firewall dans `lab-up` / `lab-down`, route, AKS en UDR | 2 | 0,36 €/h en marche | Sortie du cluster visible dans les journaux du firewall ; flux non autorisé refusé ; durées notées |
| 4 | Entrée : DNAT du firewall vers la Gateway Envoy sur load balancer interne | 2 | 0 | `hello` répond par l'IP du firewall, certificat valide |
| 5 | Foundry privé : private endpoint éphémère, zone DNS privée permanente | 0 et 2 | à vérifier | Accès public de Foundry coupé ; `ai-smoke` passe depuis le cluster |
| 6 | Passerelle IA : Envoy AI Gateway devant Foundry, quotas de tokens par équipe | 2 | 0 | Dépassement de quota refusé ; `ai-gateway` (`docs/plans/ai-gateway.md`) branché dessus |
| 7 | RAG sur niveaux gratuits (AI Search, Cosmos DB), si l'assistant d'entreprise est lancé | 0 | 0 visé | à définir |

Prérequis de l'étape 3 :
- exemption datée de la policy `azpl-deny-costly-types` pour `azureFirewalls`, limitée au
  resource group du hub ; Bastion, NAT Gateway et passerelles restent refusés ;
- rôle de `lab-down` élargi à la suppression du firewall et de ses IP (déjà approuvé) ;
- firewall ajouté au coût en direct de `cost-api` (compteurs `Basic Deployment` et
  `Basic Data Processed`).

## Coût visé

| Situation | Coût |
|---|---|
| Lab éteint, option A | Inchangé, plus les endpoints privés s'ils restent permanents |
| Soirée de lab de 4 h | Firewall 1,45 € + nœud AKS 0,76 €, soit environ 2,20 € hors données et load balancer |

## À vérifier avant d'écrire

- [ ] Durée réelle de création et de suppression d'un Azure Firewall Basic.
- [ ] Désallocation en SKU Basic (IP de management) et comportement de Terraform, si option B.
- [ ] Prix d'un private endpoint et d'une zone DNS privée en France Central.
- [ ] Niveaux gratuits : AI Search Free, Cosmos DB free tier ou serverless, Content Safety F0,
      App Configuration Free (un par subscription ou par région selon le service).
- [ ] Envoy AI Gateway : compatibilité avec la version d'Envoy Gateway déployée (v1.9.3),
      prise en charge d'Azure OpenAI v1 et de Workload Identity.
- [ ] APIM Consumption : policies `llm-token-limit` et `llm-emit-token-metric`.
- [ ] Limites du Basic acceptables : pas de DNS proxy, pas de FQDN en règle réseau, environ
      250 Mbps.

## Hors périmètre

Bastion, jumpbox, NAT Gateway, passerelle VPN, pool de build ACR dans le VNet, déploiement par
`azd`. `az aks command invoke` remplace le jumpbox ; le firewall remplace le NAT.

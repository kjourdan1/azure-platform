# Design — Plateforme AKS GitOps hébergeant AKS Store Demo

Date : 2026-10-27 · Statut : approuvé (2026-10-28)

## Intention

Kubernetes est le point faible du profil de l'auteur (ingénieur système, réseau et cloud
Azure, visant Microsoft ou le freelance). Ce chantier rend le cluster `infra/aks` utile
avec les outils qu'on trouve en entreprise (Flux, Helm, cert-manager, External Secrets,
KEDA, Prometheus/Grafana, Kyverno), en hébergeant une vraie application multi-services.

Posture retenue : **l'auteur joue l'équipe plateforme**, pas l'équipe applicative. L'appli
hébergée est **AKS Store Demo** (`Azure-Samples/aks-store-demo`), l'appli de référence de
Microsoft pour AKS, traitée comme l'appli d'une équipe produit cliente. La couche IA
(assistant d'entreprise, APIM AI gateway) vient plus tard et branchera l'`ai-service` de
la démo.

Mode de travail : chaque PR porte des explications pédagogiques et ajoute une session à
`docs/apprentissage.md`.

## Résultat visible (critère de succès)

Depuis un cluster inexistant, `lab-up` (une approbation) aboutit sans autre action à :

1. Flux réinstalle toute la plateforme puis l'appli depuis `main`.
2. `https://store.lab.killianjourdan.com` sert la boutique avec un certificat Let's Encrypt
   valide ; Grafana est exposé sur son propre sous-domaine, `store-admin` reste interne
   (`kubectl port-forward`).
3. Les mots de passe (RabbitMQ, DocumentDB, Grafana) viennent de Key Vault via External
   Secrets et Workload Identity ; aucun secret dans Git, dans les valeurs Helm ni dans un
   secret GitHub.
4. `virtual-customer` / `virtual-worker` génèrent du trafic ; KEDA scale `makeline-service`
   sur la longueur de la file RabbitMQ ; Grafana le montre.
5. Kyverno refuse un déploiement non conforme (démontrable par un `kubectl apply` raté) ;
   chaque namespace applicatif est en deny-all réseau par défaut (Cilium) avec des
   autorisations explicites.
6. `lab-down` détruit tout le soir, comme aujourd'hui.

## Objectifs, non-objectifs, anti-objectifs

Objectifs : ci-dessus, plus une CI qui valide `gitops/` et le chart sur chaque PR, et un
README qui raconte les décisions (comme les couches existantes).

Non-objectifs (v1) : `ai-service` (désactivé jusqu'à la couche IA), multi-cluster ou
multi-environnement, service mesh, SSO Entra sur Grafana, images reconstruites ou
importées dans l'ACR, sauvegarde des données de la boutique (éphémères par nature).

Anti-objectifs (échec même si « ça marche ») :
- un secret, un client ID ou un ID de tenant committé, ou un secret stocké côté GitHub ;
- une étape manuelle après `lab-up` (hors délégation NS unique chez IONOS) ;
- une ressource à coût fixe qui survit à `lab-down` au-delà de la zone DNS ;
- des exceptions de sécurité non justifiées dans le code (même règle que les
  `#checkov:skip` actuels).

## Contraintes

- **Budget** : alerte à 50 €/mois sur `azpl-lz-aks`. Cluster détruit chaque soir à 22 h UTC.
- **Policies FinOps** (`infra/landing-zone/finops.tf`) : tailles autorisées jusqu'à 4 vCPU
  (B4ms, D4s_v5…), types coûteux interdits (Application Gateway, NAT Gateway…).
- **Policies ALZ AKS** via l'add-on Azure Policy (Gatekeeper) déjà actif : pas de
  conteneurs privilégiés, etc. Tout composant installé doit les passer.
- **Dépôt public** : identifiants masqués en CI, rien d'identifiant dans Git.
- **Identité** : tout passe par OIDC / Workload Identity ; le plan est en lecture seule ;
  l'apply exige l'environnement `prd` approuvé.
- **Domaine** : `killianjourdan.com` est chez IONOS (portfolio). Seul `lab` est délégué.

## Approches considérées (installation du GitOps)

| | Approche | Pour | Contre |
|---|---|---|---|
| **A (retenue)** | Extension AKS `microsoft.flux` + `azurerm_kubernetes_flux_configuration` en Terraform dans `infra/aks` | Aucun secret (dépôt public lu anonymement), une seule étape `lab-up`, méthode documentée par Microsoft (AZ-400, cible Microsoft) | Version de Flux au rythme de Microsoft ; quelques réglages non exposés |
| B | `flux bootstrap github` dans `lab-up` | Standard CNCF, Flux s'auto-gère | Jeton GitHub en écriture stocké : casse le principe « aucun secret » |
| C | Argo CD par Helm | Le plus répandu, belle UI | Hors roadmap, UI à sécuriser (SSO), plus de travail avant la boutique |

Choisi par l'auteur : **A**. Le contenu de `gitops/` reste du Flux standard (Kustomization,
HelmRelease), transférable tel quel. Argo CD figure dans les alternatives écartées du README.

## Décisions prises avec l'auteur

- Appli hébergée : AKS Store Demo, posture équipe plateforme.
- GitOps : approche A.
- DNS : sous-zone **Azure DNS `lab.killianjourdan.com`** (≈ 0,50 €/mois), déléguée par 4
  enregistrements NS chez IONOS. Écartés : webhook external-dns IONOS (clé API donnant
  accès à tout le compte, dont `sylo.sh`), IP statique + A manuel (plus cher, manuel).
- Mode de travail : PR expliquées, relues par l'auteur.
- Gateway API (Envoy Gateway), chart maison `charts/aks-store`, `store-admin` non exposé.

## Conception

### Vue d'ensemble

```
infra/landing-zone  + provider Microsoft.KubernetesConfiguration (extension Flux)
infra/lz-aks        + zone DNS lab.killianjourdan.com
                    + identités managées (external-secrets, external-dns) et leurs rôles
infra/aks           + nœud B4s_v2, add-on KEDA
                    + extension Flux + configuration Flux (3 Kustomizations ordonnées)
                    + credentials fédérés des identités (l'émetteur OIDC change à chaque cluster)
gitops/             manifests Flux (contrôleurs, configs, applis)
charts/aks-store/   chart Helm de la plateforme pour la boutique
.github/workflows/  + validation gitops/ et chart sur PR
```

### Cluster (`infra/aks`)

- **Nœud** : `system_node_vm_size = Standard_B4s_v2` (4 vCPU, 16 Go), un nœud (le B4ms
  initialement prévu est refusé par AKS dans cette région). Un B2s (4 Go)
  ne tient pas Flux + 6 contrôleurs + Prometheus + l'appli. Coût estimé ≈ 0,20–0,25 €/h
  avec load balancer et IP : ~3 €/jour de lab. *Choix d'implémentation* : un B4s_v2 plutôt que deux
  B2s (moins de surcoût système par nœud, même plafond FinOps).
- **KEDA** via l'add-on AKS (`workload_autoscaler_profile { keda_enabled = true }`) : géré
  par Microsoft, cohérent avec l'approche A. *Choix d'implémentation.*
- **Extension Flux** : `azurerm_kubernetes_cluster_extension` (`extension_type =
  "microsoft.flux"`), puis `azurerm_kubernetes_flux_configuration` pointant sur ce dépôt,
  branche `main`, avec trois Kustomizations :
  1. `infra-controllers` → `gitops/infrastructure/controllers`
  2. `infra-configs` → `gitops/infrastructure/configs`, `depends_on` 1
  3. `apps` → `gitops/apps`, `depends_on` 2
- **Valeurs propres à l'environnement** (client IDs, URL du Key Vault, tenant, zone) :
  injectées par Flux **post-build substitution** (`${VAR}`) depuis la configuration Flux
  Terraform. Rien de tout ça dans Git. *Choix d'implémentation.*
- **Credentials fédérés** (`azurerm_federated_identity_credential`) des identités
  external-secrets et external-dns : dans `infra/aks`, car l'URL de l'émetteur OIDC est
  propre à chaque cluster et change à chaque `lab-up`. Les identités et leurs rôles, eux,
  sont permanents dans `lz-aks`.

### Prérequis permanents (`infra/lz-aks`, `infra/landing-zone`)

- `landing-zone` : ajouter `Microsoft.KubernetesConfiguration` aux resource providers de
  `lz_aks` (requis par l'extension Flux).
- `lz-aks` :
  - `azurerm_dns_zone` `lab.killianjourdan.com` ; output des name servers (à reporter une
    fois chez IONOS).
  - identité `external-dns` : rôle **DNS Zone Contributor** limité à cette zone.
  - identité `external-secrets` : rôle **Key Vault Secrets Officer** sur le coffre
    (lecture + création, voir ci-dessous).
  - Ces ressources sont permanentes (zone ≈ 0,50 €/mois, le reste gratuit).
- **Les secrets applicatifs ne sont pas gérés par Terraform** (*choix d'implémentation*). Un
  `azurerm_key_vault_secret` serait relu à chaque plan : l'identité `plan`, qui exécute le
  code des PR, devrait pouvoir lire les mots de passe, et l'identité apply n'a aucun rôle
  data-plane sur le coffre. À la place, External Secrets les crée : un générateur
  `Password` + un `PushSecret` en `updatePolicy: IfNotExists` écrit chaque mot de passe
  dans Key Vault s'il n'y existe pas encore, puis les `ExternalSecret` le relisent depuis
  Key Vault, qui reste la source de vérité. Rien dans le state, rien dans Git, aucune étape
  manuelle. Contrepartie assumée et documentée : l'identité ESO peut écrire dans ce coffre
  (dédié au cluster), d'où Secrets Officer au lieu de Secrets User.

### Contrôleurs plateforme (`gitops/infrastructure/controllers`)

HelmRepository + HelmRelease, versions épinglées, namespace par composant :

| Composant | Rôle | Identité Azure |
|---|---|---|
| cert-manager | Certificats Let's Encrypt, **HTTP-01** via la Gateway (le NSG ouvre déjà 80 pour ça) | aucune |
| Envoy Gateway | Implémentation **Gateway API** (entrée HTTP/HTTPS) | aucune |
| external-dns | Enregistrements A dans la sous-zone à partir des HTTPRoutes | Workload Identity |
| External Secrets Operator | Key Vault → Secrets Kubernetes | Workload Identity |
| kube-prometheus-stack | Prometheus, Grafana, alertes | aucune |
| Kyverno | Policies de la plateforme | aucune |

- **Gateway API + Envoy Gateway plutôt qu'Ingress** — validé par l'auteur : ingress-nginx est en fin de vie annoncée par le projet
  Kubernetes, Gateway API est le standard qui le remplace ; cert-manager et external-dns
  le supportent. Alternative : Traefik (supporte les deux).
- **Kyverno à côté d'Azure Policy** : Azure Policy (Gatekeeper) porte les garde-fous
  organisationnels venant de la landing zone ; Kyverno porte les règles de l'équipe
  plateforme, versionnées en GitOps, y compris de la génération (NetworkPolicy deny-all
  par défaut dans chaque namespace applicatif). Cette répartition va dans le README.

### Configurations (`gitops/infrastructure/configs`)

- `ClusterIssuer` Let's Encrypt (prod et staging).
- `Gateway` unique (listeners 80/443, certificat `*.lab…` ou par hôte, au choix du builder).
- `ClusterSecretStore` Azure Key Vault (Workload Identity).
- Policies Kyverno : limites de ressources obligatoires, pas de tag `latest`, registres
  autorisés (ghcr.io/azure-samples, ACR du projet, registres des charts plateforme),
  `runAsNonRoot` en audit, génération de la NetworkPolicy deny-all.
- Mode des policies : `Enforce` pour l'espace applicatif ; `Audit` là où un chart tiers
  ne s'y conforme pas, avec la raison écrite.

### Chart de la boutique (`charts/aks-store/`)

Le chart upstream ne convient pas tel quel : mots de passe en valeurs Helm, secrets
rendus en clair dans des ConfigMaps (`ORDER_QUEUE_PASSWORD`), mot de passe DocumentDB en
dur dans les arguments du conteneur, services en `LoadBalancer`. Le chart n'est publié
dans aucun dépôt Helm.

Décision (validée par l'auteur) : **un chart propre à la
plateforme**, dérivé de l'upstream (licence MIT, attribution conservée), qui coche la
case « Custom Helm chart » de la roadmap :

- secrets uniquement via `existingSecret` (créés par des `ExternalSecret`) ;
- `ClusterIP` partout ; `HTTPRoute` pour `store-front` uniquement ;
- `securityContext` restrictif là où les images le permettent ;
- `ScaledObject` KEDA (déclencheur RabbitMQ, longueur de la file `orders`) pour
  `makeline-service`, avec `TriggerAuthentication` depuis le secret ;
- `ServiceMonitor` là où un endpoint de métriques existe (RabbitMQ a un plugin
  Prometheus) ;
- NetworkPolicies d'autorisation explicite entre services ;
- images upstream `ghcr.io/azure-samples/aks-store-demo/*` en tag épinglé ;
- `ai-service` absent.

Déployé par une HelmRelease dans `gitops/apps/store`, avec les `ExternalSecret`.

### Exposition

- `store.lab.killianjourdan.com` et `grafana.lab.killianjourdan.com` (mot de passe admin
  Grafana venant de Key Vault).
- `store-admin` n'a aucune authentification upstream : **non exposé** (décision de
  l'auteur), accès par `kubectl port-forward`. Exposition derrière oauth2-proxy + Entra ID
  possible plus tard.

### CI (`.github/workflows/gitops-pr.yml`)

Sur PR touchant `gitops/**` ou `charts/**` : `helm lint` + `helm template` du chart,
`kustomize build` de chaque répertoire, `kubeconform` (avec schémas des CRD utilisées),
`kyverno test` / `kyverno apply` des policies contre le rendu du chart. Aucun accès Azure.

### Cycle de vie

- `lab-up` : inchangé côté workflow ; l'apply de `infra/aks` crée cluster, extension,
  configuration Flux et credentials fédérés. Flux converge ensuite seul (objectif < 15 min).
- `lab-down` : inchangé ; la suppression du cluster emporte extension et configuration.
- **Limite Let's Encrypt** : 5 certificats identiques par semaine. Un `lab-up` quotidien
  avec émission neuve peut l'atteindre. v1 : issuer prod, limite documentée, staging pour
  les essais. Amélioration ultérieure : sauvegarde du certificat dans Key Vault
  (PushSecret ESO) et restauration au `lab-up` suivant.

## Découpage en PR (ordre proposé)

1. **Socle** : provider KubernetesConfiguration, zone DNS + identités (`lz-aks`),
   nœud B4s_v2 + KEDA + extension et configuration Flux + credentials fédérés (`infra/aks`),
   squelette `gitops/`, workflow de validation `gitops-pr`.
2. **Entrée et secrets** : cert-manager, Envoy Gateway, external-dns, ESO (générateurs +
   PushSecret) + leurs configs.
   Démo : une page de test en HTTPS.
3. **Chart et boutique** : `charts/aks-store`, HelmRelease, ExternalSecrets, HTTPRoutes.
4. **Observabilité et scaling** : kube-prometheus-stack, ServiceMonitors, ScaledObject KEDA,
   tableau de bord Grafana.
5. **Gouvernance** : Kyverno, policies, NetworkPolicies, tests de policies en CI.
6. **Récit** : README racine et READMEs de couche, statut de la roadmap.

Chaque PR : description pédagogique + session dans `docs/apprentissage.md`.

## Risques

- Un composant tiers refusé par les policies ALZ AKS (node-exporter utilise `hostNetwork`
  / `hostPID`) : vérifier l'effet des assignations, sinon exemption ciblée justifiée.
- Mémoire du nœud unique : mesurer après la PR 4 ; limiter la rétention Prometheus.
- Ordre de convergence Flux (CRD avant ressources) : géré par les `depends_on` et
  `wait`/`healthChecks`.
- Identifiants substitués (client IDs, tenant) marqués `sensitive` pour rester hors des
  logs publics du plan.
- Disponibilité et format de l'extension Flux et de ses champs dans le provider azurerm
  épinglé (`~> 5.10`) : à vérifier en PR 1.

## Laissé au builder

Versions exactes des charts, structure fine de `gitops/` sous les trois racines, choix
certificat wildcard ou par hôte, détails des tableaux de bord, formulation des policies.

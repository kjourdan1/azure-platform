# GitOps

## Problème résolu
Le cluster est détruit chaque soir. Tout ce qui y tourne doit donc pouvoir revenir seul,
identique, à partir de Git : contrôleurs de la plateforme, leurs configurations et les
applications hébergées.

## Approche retenue
Flux, installé par l'extension AKS (`infra/aks/gitops.tf`), lit ce dossier sur `main` et
réconcilie en continu l'état du cluster avec son contenu. Trois niveaux, appliqués dans
l'ordre, chacun attendant que le précédent soit sain :

| Niveau | Dossier | Contenu |
|---|---|---|
| 1 | `infrastructure/controllers` | Contrôleurs (HelmRelease) et leurs CRD |
| 2 | `infrastructure/configs` | Objets qui utilisent ces CRD : ClusterIssuer, Gateway, ClusterSecretStore, policies |
| 3 | `apps` | Applications hébergées |

### Ce qui tourne

| Niveau | Composant | Rôle | Identité Azure |
|---|---|---|---|
| 1 | Envoy Gateway v1.9.3 | Implémentation Gateway API ; installe aussi les CRD Gateway API | aucune |
| 1 | cert-manager v1.21.3 | Certificats Let's Encrypt (HTTP-01 via la Gateway) ; attend Envoy Gateway, car il ne détecte Gateway API qu'au démarrage | aucune |
| 1 | External Secrets 2.14.0 | Key Vault ↔ Secrets Kubernetes | Workload Identity (`external-secrets`) |
| 1 | external-dns 1.23.0 | Enregistrements de `lab.killianjourdan.com` tirés des HTTPRoute | Workload Identity (`external-dns`) |
| 2 | `ClusterIssuer` prod / staging, `Gateway platform`, `ClusterSecretStore azure-key-vault` | Configurations partagées | |
| 3 | `demo` (podinfo) | `https://hello.lab.killianjourdan.com`, preuve du chemin d'un secret | |

### Le chemin d'un secret (`apps/demo/secret-path.yaml`)

```
générateur Password ──► Secret « graine » ──► PushSecret ──► Key Vault (contentType, expiration)
                                                                   │
                     page de démo ◄── Secret demo-greeting ◄── ExternalSecret
```

La valeur affichée sur la page a fait l'aller-retour par Key Vault : aucune valeur dans Git,
dans Terraform ni dans GitHub. Key Vault impose (policy ALZ `Enforce-GR-KeyVault`, Deny) un
`contentType` et une validité de 90 jours au plus : la date d'expiration est calculée par
Terraform (`time_rotating`, variable `${SECRET_EXPIRES_AT}`) et repoussée à chaque `lab-up`.

## Décisions et alternatives écartées
- **Ordre explicite** (`depends_on` + `wait` dans la configuration Flux) : sans lui, un
  `ClusterIssuer` serait appliqué avant que cert-manager ait installé sa CRD, et échouerait.
- **Aucun identifiant dans Git** : les valeurs propres à l'environnement arrivent par
  post-build substitution. Variables disponibles dans tous les manifests :

  | Variable | Contenu |
  |---|---|
  | `${AZURE_TENANT_ID}` | Tenant Entra |
  | `${AZURE_SUBSCRIPTION_ID}` | Subscription `azpl-lz-aks` |
  | `${DNS_ZONE}` | `lab.killianjourdan.com` |
  | `${DNS_RESOURCE_GROUP}` | Resource group de la zone |
  | `${KEY_VAULT_URL}` | URI du Key Vault du cluster |
  | `${ESO_CLIENT_ID}` | Client ID de l'identité External Secrets |
  | `${EXTERNAL_DNS_CLIENT_ID}` | Client ID de l'identité external-dns |
  | `${SECRET_EXPIRES_AT}` | Date d'expiration des secrets écrits dans Key Vault (30 à 60 jours) |

  La liste fait foi dans `infra/aks/locals.tf` (`flux_substitutions`).
- **Gateway API plutôt qu'Ingress** : ingress-nginx est en fin de vie annoncée, Gateway API
  le remplace. Un listener HTTPS par nom exposé : le nom fixe le certificat émis.
- **Policies ALZ dans le cluster** : Gatekeeper refuse tout conteneur sans
  `allowPrivilegeEscalation: false` explicite. cert-manager, External Secrets, external-dns et
  Envoy Gateway s'y conforment par défaut ; podinfo reçoit un `securityContext`.
- **Contrôle en CI** (`gitops-pr`) : Flux remplace une variable inconnue par une chaîne vide,
  sans erreur ; `scripts/check-substitutions.sh` la refuse avant le merge.
  `scripts/validate-gitops.py` construit chaque niveau, substitue des valeurs d'exemple, valide
  contre les schémas Kubernetes et ceux des CRD (`kubeconform`), puis rend chaque HelmRelease
  (`helm template`) et applique la règle de Gatekeeper à chaque conteneur.
  En local : `python3 scripts/validate-gitops.py` (kustomize, kubeconform et helm dans le PATH).

## Limites connues
- **Let's Encrypt** : 5 certificats identiques par semaine ; chaque `lab-up` en réémet un par
  nom. Pour des essais répétés, passer la Gateway sur `letsencrypt-staging`.
- **Enregistrements DNS orphelins** : après `lab-down`, l'enregistrement A pointe vers une IP
  libérée jusqu'au `lab-up` suivant. À corriger : faire vider la sous-zone par `lab-down`.
- Une modification sur `main` est prise en compte au prochain cycle de synchronisation
  (10 minutes) ou immédiatement avec `flux reconcile` / un `lab-up`.

## Vérification
```
kubectl get kustomizations -n flux-system
kubectl get helmreleases -A
kubectl get gateway -n gateway platform          # adresse publique
kubectl get certificate -A                        # hello-tls Ready
kubectl get externalsecrets,pushsecrets -n demo  # SecretSynced / Synced
curl -sI https://hello.lab.killianjourdan.com
```

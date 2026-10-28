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

  La liste fait foi dans `infra/aks/locals.tf` (`flux_substitutions`).
- **Contrôle en CI** (`gitops-pr`) : Flux remplace une variable inconnue par une chaîne vide,
  sans erreur ; `scripts/check-substitutions.sh` la refuse avant le merge. Chaque niveau est
  aussi construit (`kustomize build`) et validé contre les schémas Kubernetes (`kubeconform`).

## Limites connues
- Les CRD des contrôleurs ne sont pas encore validées par schéma (`-ignore-missing-schemas`).
- Une modification sur `main` est prise en compte au prochain cycle de synchronisation
  (10 minutes) ou immédiatement avec `flux reconcile` / un `lab-up`.

## Vérification
`kubectl get kustomizations -n flux-system` puis
`kubectl get cm cluster-info -n flux-system -o jsonpath='{.data.dnsZone}'`.

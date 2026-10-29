# PR 2 — Entrée HTTPS et chemin des secrets : plan d'implémentation

**Goal :** après un `lab-up`, `https://hello.lab.killianjourdan.com` sert une page de démo en
HTTPS (Let's Encrypt), et la page affiche une valeur générée dans le cluster, stockée dans Key
Vault puis relue depuis Key Vault par External Secrets.

**Design :** `docs/design/aks-gitops-store.md` (sections contrôleurs, configurations, cycle de
vie). Ce plan fixe les versions, l'ordre et les contraintes découvertes en vérifiant Azure.

## Contraintes vérifiées (ne pas redécouvrir)

- **Gatekeeper (policies ALZ en Deny dans le cluster)** : `Deny-Priv-Esc-AKS` refuse tout
  conteneur sans `securityContext.allowPrivilegeEscalation: false` explicite ;
  `Deny-Privileged-AKS` refuse `privileged: true` ; `Enforce-AKS-HTTPS` ne vise que les
  `Ingress` (pas Gateway API). Rendu `helm template` vérifié : cert-manager, External
  Secrets, external-dns, contrôleur Envoy Gateway conformes par défaut ; pods Envoy créés à
  l'exécution conformes (`DefaultSecurityContext()` dans le code d'Envoy Gateway) ; podinfo
  **non conforme** par défaut → `securityContext` à fournir.
- **Key Vault (`Enforce-GR-KeyVault`, Deny)** : `contentType` obligatoire, validité de
  90 jours au plus (date d'expiration obligatoire). Le `PushSecret` Azure d'ESO accepte
  `contentType` et `expirationDate` (date RFC3339 fixe, pas relative).
- **cert-manager + Gateway API** : `config.gatewayAPI.enabled: true`, et les CRD Gateway API
  doivent exister **avant** le démarrage de cert-manager (vérification au démarrage seulement).
  Le chart Envoy Gateway installe ces CRD (`crds.enabled: true` par défaut).
- **Let's Encrypt** : 5 certificats identiques par semaine et par ensemble de noms. Chaque
  `lab-up` en réémet un : à surveiller, issuer `letsencrypt-staging` disponible pour les essais.

## Versions épinglées

| Chart | Source | Version |
|---|---|---|
| envoy-gateway (`gateway-helm`) | `oci://docker.io/envoyproxy` | v1.9.3 |
| cert-manager | `https://charts.jetstack.io` | v1.21.3 |
| external-dns | `https://kubernetes-sigs.github.io/external-dns` | 1.23.0 |
| external-secrets | `https://charts.external-secrets.io` | 2.14.0 |
| podinfo (démo) | `https://stefanprodan.github.io/podinfo` | 6.17.0 |

## Tâches

### 1. `infra/aks` : date d'expiration des secrets
- `time_rotating.secret_expiry` (provider `hashicorp/time`, `rotation_days = 30`) ;
  substitution `SECRET_EXPIRES_AT = timeadd(time_rotating.secret_expiry.rfc3339, "1440h")` :
  expiration entre 30 et 60 jours dans le futur, sous la limite ALZ de 90 jours, sans
  changer à chaque plan (une `plantimestamp()` rendrait chaque plan différent).
- Vérif : `terraform validate`, `tflint`, `checkov`, plan local.

### 2. Niveau 1 — contrôleurs (`gitops/infrastructure/controllers/<composant>/`)
Un dossier par composant : `namespace.yaml`, `repository.yaml` (HelmRepository),
`release.yaml` (HelmRelease, `install.crds`/`upgrade.crds: CreateReplace` quand le chart les
porte en `crds/`).
- `envoy-gateway` (ns `envoy-gateway-system`) : valeurs par défaut.
- `cert-manager` (ns `cert-manager`) : `crds.enabled: true`, `config.gatewayAPI.enabled: true`,
  `dependsOn: envoy-gateway`.
- `external-secrets` (ns `external-secrets`) : SA `external-secrets` annoté
  `azure.workload.identity/client-id: ${ESO_CLIENT_ID}`, pods labellisés
  `azure.workload.identity/use: "true"`.
- `external-dns` (ns `external-dns`) : provider `azure`, sources `gateway-httproute`,
  `domainFilters: [${DNS_ZONE}]`, `policy: sync`, `txtOwnerId: aks-azpl` ; fichier
  `azure.json` (tenant, subscription, resource group, `useWorkloadIdentityExtension: true`)
  dans un Secret de la Kustomization ; SA `external-dns` annoté `${EXTERNAL_DNS_CLIENT_ID}`,
  pods labellisés Workload Identity.

### 3. Niveau 2 — configurations (`gitops/infrastructure/configs/`)
- `cluster-issuers.yaml` : `letsencrypt-prod` et `letsencrypt-staging`, HTTP-01 via
  `gatewayHTTPRoute` (parentRef : Gateway `platform`, ns `gateway`).
- `gateway.yaml` : namespace `gateway`, `GatewayClass envoy`, `Gateway platform` annotée
  `cert-manager.io/cluster-issuer: letsencrypt-prod`, listeners `http` (80, routes de tous
  namespaces) et `https-hello` (443, `hello.${DNS_ZONE}`, secret `hello-tls`) ; `HTTPRoute`
  de redirection HTTP→HTTPS (le chemin ACME, plus spécifique, reste prioritaire).
- `cluster-secret-store.yaml` : `ClusterSecretStore azure-key-vault`, `authType:
  WorkloadIdentity`, `vaultUrl: ${KEY_VAULT_URL}`, SA `external-secrets/external-secrets`.

### 4. Niveau 3 — démo (`gitops/apps/demo/`)
Chaîne complète du secret, visible sur la page :
1. générateur `Password` → `ExternalSecret demo-greeting-seed` (`refreshInterval: "0"` :
   généré une fois par cluster) ;
2. `PushSecret` → Key Vault `demo-greeting`, `updatePolicy: Replace`,
   `contentType: text/plain`, `expirationDate: ${SECRET_EXPIRES_AT}` ;
3. `ExternalSecret demo-greeting` lit Key Vault ;
4. podinfo (`ui.message` via `extraEnvs` `PODINFO_UI_MESSAGE` depuis ce secret),
   `securityContext` conforme Gatekeeper ;
5. `HTTPRoute hello` → `hello.${DNS_ZONE}`, listener `https-hello`.

### 5. CI
- `gitops-pr` : schémas des CRD (Flux, Gateway API, cert-manager, ESO) via le catalogue
  datreeio pour `kubeconform`.
- Nouveau contrôle : rendu `helm template` de chaque HelmRelease avec ses valeurs, puis
  vérification `allowPrivilegeEscalation: false` / pas de `privileged` sur chaque conteneur
  (même règle que Gatekeeper, détectée avant le cluster).

### 6. Docs
README `gitops/` (composants, ordre, chemin du secret), `infra/aks` (expiration), README
racine (statut), `docs/apprentissage.md` session 4.

## Vérification après `lab-up`
1. `kubectl get kustomizations,helmreleases -A` : tout `Ready`.
2. `kubectl get gateway -n gateway platform` : adresse publique ; `kubectl get certificate -A`.
3. `nslookup hello.lab.killianjourdan.com` = IP de la Gateway.
4. `curl -sI https://hello.lab.killianjourdan.com` : 200, certificat Let's Encrypt valide.
5. La page affiche la valeur ; `az keyvault secret show --vault-name <kv> -n demo-greeting
   --query "{type:contentType, exp:attributes.expires}"`.

## Risques connus
- **Enregistrements DNS orphelins** après `lab-down` : l'IP publique est libérée, l'enregistrement
  A reste jusqu'au `lab-up` suivant (risque de reprise de sous-domaine si l'IP est réattribuée).
  Suite prévue : `lab-down` vide les enregistrements A de la sous-zone.
- Quota Let's Encrypt (voir plus haut).

# ai-gateway — état et reprise

Console sur AKS : coût de tout le lab (facturé et en direct) et assistant branché sur
Foundry, avec les tokens et le coût de chaque échange. Trois microservices (`web`,
`cost-api`, `chat-api`) derrière la Gateway Envoy, authentification Entra ID (OIDC).
Architecture et décisions : `apps/ai-gateway/README.md`.

## Où on en est

| Étape | Branche | État |
|---|---|---|
| 1a. Identités `ai-chat`, `ai-cost`, `build` (lz-aks) | `feat/ai-gateway-infra` | Poussée, PR à ouvrir. Plan `7 to add, 0 to change, 0 to destroy` |
| 1b. Inférence Foundry pour `ai-chat` (infra/ai) | `feat/ai-gateway-access` | Poussée. À ouvrir **après l'apply de 1a** (lit `principal_id` dans le state de lz-aks) |
| 2. Application et workflow `build-images` | `feat/ai-gateway-app` | Poussée, PR à ouvrir. 25 tests, cost-api vérifié contre les vraies API, images testées en lecture seule et non root |
| 3. Déploiement : fédération des identités (infra/aks), manifests Flux, route, OIDC, limite de débit, NetworkPolicies | `feat/ai-gateway-deploy` | Poussée. 26 ressources validées (kubeconform strict, règle Gatekeeper). **Non mergeable tant que le tag des images vaut `unset`** : la validation échoue exprès |

## Ordre de reprise

1. Ouvrir et merger **1a**, approuver `apply-lz-aks`.
2. Dans Cloud Shell : `terraform -chdir=infra/lz-aks output -raw build_client_id`, à mettre
   dans le secret de dépôt `AZURE_CLIENT_ID_BUILD`.
3. Ouvrir et merger **1b** (plan attendu : `1 to add`), approuver `apply-ai`.
4. Ouvrir et merger **2** : `build-images` publie les trois images dans ACR. Le tag est
   affiché dans le résumé du run (12 premiers caractères du commit de `main`).
   Si Trivy bloque sur une vulnérabilité corrigeable, corriger la base avant de merger.
5. App registration `azpl-ai-gateway` (à la main) :
   - redirect URI web `https://ai.lab.killianjourdan.com/oauth2/callback` ;
   - Enterprise application → *Assignment required* = Yes, s'assigner ;
   - client ID dans le secret de dépôt `AI_GATEWAY_CLIENT_ID` (jamais dans Git) ;
   - client secret de 90 jours au plus, déposé dans le Key Vault du cluster (la policy exige
     `contentType` et une expiration ; la valeur est saisie sans écho, hors historique) :
     ```bash
     read -rs S
     az keyvault secret set --vault-name kv-azpl-aks-prd-frc-001 \
       --name ai-gateway-oidc-client-secret --content-type text/plain \
       --expires "$(date -u -d '+85 days' +%Y-%m-%dT%H:%M:%SZ)" --value "$S" --query id -o tsv
     unset S
     ```
     Il faut le rôle Key Vault Secrets Officer sur ce coffre.
6. Sur `feat/ai-gateway-deploy` : remplacer les trois `newTag: unset` de
   `gitops/apps/ai-gateway/kustomization.yaml` par le tag de l'étape 4, ouvrir la PR
   (`gitops-pr` et le plan de `infra/aks` doivent être verts), merger.
7. `lab-up`, puis vérifier (voir plus bas) et capture d'écran pour le README.

## Vérification après `lab-up`

Rien de ce qui suit n'a pu être testé hors cluster.

1. `kubectl get pods,httproute,securitypolicy,backendtrafficpolicy -n ai-gateway` : pods
   `Running`, policies `Accepted`.
2. `kubectl get externalsecret -n ai-gateway` : `SecretSynced`.
3. Navigation privée sur `https://ai.lab.killianjourdan.com` : redirection vers la connexion
   Microsoft ; un compte non assigné est refusé.
4. Console : coûts affichés (Workload Identity de `cost-api`), réponse du modèle en streaming
   avec tokens et coût (Workload Identity de `chat-api`).
5. Plus de 20 messages en une minute : réponse 429.
6. `curl -sI` sur l'URL sans cookie : 302, jamais 200.

Si une `SecurityPolicy` n'est pas `Accepted`, ne pas laisser la route exposée : retirer
`ai-gateway` de `gitops/apps/kustomization.yaml` le temps de corriger.

## Textes des PR

### 1a — `feat(lz-aks): ai-gateway workload identities and image build identity`

```markdown
## Why
ai-gateway runs as three microservices on AKS. Each one that talks to Azure gets its own identity with least privilege.

## Changes (infra/lz-aks)
- `ai-chat` identity: inference on Foundry (role assigned by infra/ai in the next PR).
- `ai-cost` identity: Cost Management Reader + Reader on the `alz` management group, inherited by all 4 subscriptions. Read-only.
- `build` identity: AcrPush on the registry, federated to `refs/heads/main` only, so a PR can never publish an image.
- Outputs: `principal_id` added to `workload_identities`, plus `container_registry_login_server` and `build_client_id`.
- Existing identities (`external_secrets`, `external_dns`) keep their keys: no reassignment.

## Plan
`7 to add, 0 to change, 0 to destroy`.
```

### 1b — `feat(ai): Foundry inference for the ai-gateway chat-api`

```markdown
## Why
chat-api calls the Foundry deployment with its Workload Identity, without a key.

## Changes (infra/ai)
- Remote state of lz-aks, to read the `ai-chat` identity.
- `Cognitive Services OpenAI User` on the Foundry account for `ai-chat`: inference only, same as ai-smoke.

## Plan
`1 to add, 0 to change, 0 to destroy`. Requires the lz-aks apply of the previous PR.
```

### 2 — `feat(ai-gateway): cost and Foundry console as three microservices`

```markdown
## Why
A console on AKS that shows what the whole lab costs (billed and live) and talks to the Foundry deployment, with tokens and cost per exchange.

## Changes
- `apps/ai-gateway/web`: nginx-unprivileged, static HTML/CSS/JS with no framework, strict CSP.
- `apps/ai-gateway/cost-api`: billed cost (Cost Management, 30 days, by subscription and service), live cost (Resource Graph × public prices, real meter names), model prices; server-side caches that serve the last value when Azure fails.
- `apps/ai-gateway/chat-api`: streams from Foundry (SSE), exact usage at the end, cost per exchange, guardrails (roles, size, history, max tokens, concurrency).
- `.github/workflows/build-images.yml`: tests, build, Trivy scan (HIGH/CRITICAL fixable blocks), push to ACR from `main` only, tag = commit.

## Validation
- 25 unit tests.
- cost-api run against the real Azure APIs.
- Images run read-only, non-root, no capabilities.
```

### 3 — `feat(ai-gateway): GitOps deployment behind Entra ID`

```markdown
## Why
Deploys the ai-gateway console on the cluster, reachable only by accounts assigned to the Entra application.

## Changes
- `gitops/apps/ai-gateway`: three hardened Deployments (non-root, read-only filesystem, no capabilities), one ServiceAccount per service with its Workload Identity, path-based routes on `ai.<zone>`, Entra ID OIDC at the Gateway, rate limit on the chat route, default-deny ingress NetworkPolicies.
- `gitops/infrastructure/configs/gateway.yaml`: HTTPS listener and certificate for `ai.<zone>`.
- `infra/aks`: federated credentials for `ai-chat` and `ai-cost`, Flux substitutions, `ai_gateway_client_id` variable (required, GUID-validated).
- Workflows: `AI_GATEWAY_CLIENT_ID` secret passed to Terraform.
- `scripts/validate-gitops.py`: fails on an image without a real tag.

## Validation
- 26 resources valid (kubeconform strict, Envoy Gateway CRDs included), Gatekeeper rule passes.
- Not testable outside the cluster: OIDC sign-in, rate limit, Workload Identity. Checklist in `docs/plans/ai-gateway.md`.
```

## Points à surveiller
- Trivy n'a pas pu tourner en local (base de vulnérabilités bloquée par le réseau du poste
  de travail) : premier vrai scan dans la CI de la PR 2.
- Le coût « en direct » ne valorise que les types connus (nœuds, disques Premium, IP, load
  balancer, ACR, plan de contrôle AKS, zones DNS). Un futur Azure Firewall devra y être ajouté.

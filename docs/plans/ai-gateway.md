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
| 1c. Fédération des identités et substitutions Flux (infra/aks) | à écrire | Après 1a |
| 3. Manifests Flux, route, OIDC, limite de débit, NetworkPolicies | à écrire | Après 1c et l'app registration |

## Ordre de reprise

1. Ouvrir et merger **1a**, approuver `apply-lz-aks`.
2. Dans Cloud Shell : `terraform -chdir=infra/lz-aks output -raw build_client_id`, à mettre
   dans le secret de dépôt `AZURE_CLIENT_ID_BUILD`.
3. Ouvrir et merger **1b** (plan attendu : `1 to add`), approuver `apply-ai`.
4. Ouvrir et merger **2** : `build-images` publie les trois images dans ACR (tag = commit).
   Si Trivy bloque sur une vulnérabilité corrigeable, corriger la base avant de merger.
5. App registration `azpl-ai-gateway` (à la main) :
   - redirect URI web `https://ai.lab.killianjourdan.com/oauth2/callback` ;
   - Enterprise application → *Assignment required* = Yes, s'assigner ;
   - client secret de 90 jours au plus, déposé dans le Key Vault du cluster (commande fournie
     avec la PR 3 : `contentType` et date d'expiration exigés par la policy) ;
   - le client ID va dans le secret de dépôt `AI_GATEWAY_CLIENT_ID` (jamais dans Git).
6. Écrire **1c** puis **3**, `lab-up`, capture d'écran pour le README.

## 1c — à écrire (infra/aks)

- `workload_identity_subjects` : `ai_chat = "ai-gateway:chat-api"`, `ai_cost = "ai-gateway:cost-api"`.
- Remote state `ai` (clé `ai.tfstate`) pour `foundry_endpoint` et `chat_deployment`.
- `flux_substitutions` : `AI_CHAT_CLIENT_ID`, `AI_COST_CLIENT_ID`, `FOUNDRY_ENDPOINT`,
  `FOUNDRY_DEPLOYMENT`, `ACR_LOGIN_SERVER` (output `container_registry_login_server`),
  `AI_GATEWAY_CLIENT_ID` (variable alimentée par le secret, dans `lab-up` et `terraform-pr`).

## 3 — à écrire (gitops/apps/ai-gateway)

- Namespace `ai-gateway` ; un ServiceAccount par service, annoté avec son client ID,
  pods labellisés `azure.workload.identity/use: "true"` (cost-api, chat-api).
- Deployments durcis (Gatekeeper) : `runAsNonRoot`, `readOnlyRootFilesystem`, `emptyDir`
  sur `/tmp` (nginx en a besoin), `allowPrivilegeEscalation: false`, capabilities `drop: ALL`,
  probes `/healthz`, requests/limits ; images `${ACR_LOGIN_SERVER}/ai-gateway/<svc>:<commit>`.
- Services ClusterIP (port 80) ; `chat-api` appelle `http://cost-api`.
- HTTPRoute `ai.${DNS_ZONE}` : `/api/cost` → cost-api, `/api/chat` → chat-api, `/` → web ;
  listener HTTPS dédié et certificat Let's Encrypt sur la Gateway.
- `SecurityPolicy` OIDC (issuer `https://login.microsoftonline.com/${AZURE_TENANT_ID}/v2.0`,
  secret client relu par ESO dans le namespace de la policy), `logoutPath: /logout`.
- `BackendTrafficPolicy` : limite de débit locale sur `/api/chat`.
- NetworkPolicies (Cilium) : entrée depuis la Gateway seulement ; `chat-api` → `cost-api`.
- Le bouton « Se déconnecter » du front pointe déjà sur `/logout`.

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

## Points à surveiller
- Trivy n'a pas pu tourner en local (base de vulnérabilités bloquée par le réseau du poste
  de travail) : premier vrai scan dans la CI de la PR 2.
- Le coût « en direct » ne valorise que les types connus (nœuds, disques Premium, IP, load
  balancer, ACR, plan de contrôle AKS, zones DNS). Un futur Azure Firewall devra y être ajouté.

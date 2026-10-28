# Plateforme AKS GitOps — Plan d'implémentation

**Goal:** Un `lab-up` qui crée le cluster AKS avec Flux branché sur `main`, puis (PR suivantes) la plateforme et AKS Store Demo réinstallées depuis Git.

**Architecture:** Les identités, la zone DNS et le Key Vault sont permanents dans `infra/lz-aks`. Le cluster, l'extension Flux, la configuration Flux et les credentials fédérés sont éphémères dans `infra/aks`. Tout le contenu du cluster vit dans `gitops/` : trois Kustomizations Flux ordonnées (controllers → configs → apps), avec les valeurs d'environnement injectées par post-build substitution depuis Terraform.

**Tech Stack:** Terraform 1.16.6, azurerm 5.11.0 (lock existant), extension AKS `microsoft.flux`, Kustomize, kubeconform, GitHub Actions.

**Spec:** `docs/design/aks-gitops-store.md`

Ce plan détaille **PR 1 (Socle)**. La PR 1 est livrée en deux temps : **1a** (Tasks 1-2, plus README et apprentissage) puis **1b** (Tasks 3-5) une fois 1a appliquée, car `infra/aks` lit des outputs de `lz-aks` qui n'existent dans le state qu'après l'apply. Les PR 2 à 6 sont esquissées en fin de document et recevront chacune leur plan détaillé une fois la précédente mergée et testée par un `lab-up` : chacune dépend de ce que le cluster réel aura montré.

## Global Constraints

- Aucun secret, client ID, tenant ID ou subscription ID dans Git ; valeurs passées au cluster par `post_build.substitute`, marquées `sensitive()` côté Terraform.
- Les secrets applicatifs ne sont pas gérés par Terraform (ESO générateur + PushSecret, PR 2).
- Nommage : `<type>-azpl-<composant>-prd-frc-001` (`local.suffix`), tags `local.tags` existants.
- Tailles de VM dans la liste FinOps de `infra/landing-zone/finops.tf` ; nœud `Standard_B4ms`.
- Tout `#checkov:skip` porte sa justification en français sur la même ligne, comme l'existant.
- Commentaires et READMEs en français, au style des couches existantes (problème / approche / décisions / limites).
- Dépôt : `https://github.com/kjourdan1/azure-platform`, branche `main`, lu anonymement par Flux.
- Chaque PR ajoute une session à `docs/apprentissage.md` (checklist cochée seulement après démonstration).

## Review Focus

1. **Plan public qui fuit des identifiants** : un client ID ou un tenant ID qui apparaît en clair dans la sortie `terraform plan` d'une PR. Attendu : `(sensitive value)`. → Task 3 step 5.
2. **`lab-up` après `lab-down`** : le state de `infra/aks` contient l'extension, la config Flux et les credentials fédérés d'un cluster supprimé. Attendu : le plan recrée le tout, sans erreur ni « already exists ». → vérification post-merge 4.
3. **Kustomization mal ordonnée** : `infra-configs` démarre avant que les CRD de `infra-controllers` existent. Attendu : `depends_on` + `wait = true` rendent l'ordre déterministe. → Task 3 step 3.
4. **Variable de substitution manquante** : un `${VAR}` dans `gitops/` absent de la map Terraform est remplacé silencieusement par une chaîne vide. Attendu : la CI échoue. → Task 4 steps 1-2.
5. **Délégation NS non faite** : la zone existe mais IONOS ne délègue pas. Attendu : procédure et commande de vérification `dig NS lab.killianjourdan.com` dans le README de `lz-aks`. → Task 2 step 5.

---

### Task 1: Provider `Microsoft.KubernetesConfiguration` sur la subscription lz-aks

**Files:**
- Modify: `infra/landing-zone/subscriptions.tf` (map `resource_providers`)

**Interfaces:**
- Produces : le provider enregistré, requis par `azurerm_kubernetes_cluster_extension` (Task 3).

- [ ] **Step 1:** Ajouter `"Microsoft.KubernetesConfiguration" = []` à `resource_providers`, ordre alphabétique conservé.
- [ ] **Step 2:** Vérifier.
  Run : `cd infra/landing-zone && terraform fmt -check && terraform init -backend=false >/dev/null && terraform validate`
  Attendu : `Success! The configuration is valid.`
- [ ] **Step 3:** Commit `feat(landing-zone): enregistrer Microsoft.KubernetesConfiguration pour l'extension Flux`.

### Task 2: Zone DNS et identités de charge de travail (`infra/lz-aks`)

**Files:**
- Create : `infra/lz-aks/dns.tf`, `infra/lz-aks/workload-identities.tf`
- Modify : `infra/lz-aks/variables.tf`, `infra/lz-aks/outputs.tf`, `infra/lz-aks/README.md`

**Interfaces:**
- Produces (outputs de `lz-aks`, lus par `infra/aks` via `local.lz_aks`) :
  - `dns_zone` : `object({ id, name, resource_group_name })`
  - `dns_zone_name_servers` : `list(string)`
  - `key_vault_uri` : `string`
  - `workload_identities` : `map(object({ id = string, client_id = string }))`, clés `external_secrets`, `external_dns` — `sensitive = true`
  - `subscription_id` : `string`, `sensitive = true`

- [ ] **Step 1:** Variable `dns_zone_name` (string, défaut `"lab.killianjourdan.com"`, description : sous-zone déléguée depuis IONOS).
- [ ] **Step 2:** `dns.tf` : `azurerm_dns_zone.lab` dans `azurerm_resource_group.shared`, `lifecycle { prevent_destroy = true }` (les NS changeraient et casseraient la délégation chez IONOS). Commentaire : pourquoi Azure DNS plutôt que l'API IONOS (clé API à portée compte entier).
- [ ] **Step 3:** `workload-identities.tf` : une map locale qui associe à chaque clé son rôle et son scope (`external_secrets` → « Key Vault Secrets Officer » sur le coffre, `external_dns` → « DNS Zone Contributor » sur la zone) ; `azurerm_user_assigned_identity` en `for_each` (nom `id-azpl-${replace(key, "_", "-")}-${local.suffix}`), `azurerm_role_assignment` en `for_each`. Commentaires : Secrets Officer car ESO crée les mots de passe absents (PushSecret, spec § prérequis) ; pas de credential fédéré ici car l'émetteur OIDC change à chaque cluster.
- [ ] **Step 4:** Outputs listés dans Interfaces.
- [ ] **Step 5:** README `lz-aks` : section DNS (délégation : les 4 NS de `az network dns zone show -g <rg> -n lab.killianjourdan.com --query nameServers` à créer chez IONOS sur l'hôte `lab` ; vérification `dig +short NS lab.killianjourdan.com`), section identités.
- [ ] **Step 6:** Vérifier.
  Run : `cd infra/lz-aks && terraform fmt -check && terraform init -backend=false >/dev/null && terraform validate && tflint --init --config ../../.tflint.hcl >/dev/null && tflint --config ../../.tflint.hcl`
  Attendu : valide, tflint sans sortie.
- [ ] **Step 7:** Si checkov est installable (venv dans le scratchpad), `checkov -d infra/lz-aks --framework terraform --quiet` : aucun échec non justifié.
- [ ] **Step 8:** Commit `feat(lz-aks): zone DNS lab et identités external-secrets / external-dns`.

### Task 3: Nœud, KEDA, extension et configuration Flux (`infra/aks`)

**Files:**
- Create : `infra/aks/gitops.tf`, `infra/aks/workload-identities.tf`
- Modify : `infra/aks/variables.tf` (défaut `system_node_vm_size = "Standard_B4ms"` + description), `infra/aks/cluster.tf` (bloc `workload_autoscaler_profile { keda_enabled = true }`), `infra/aks/locals.tf`, `infra/aks/README.md`

**Interfaces:**
- Consumes : outputs de Task 2 via `local.lz_aks`.
- Produces : variables de substitution disponibles dans tout `gitops/` :
  `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `DNS_ZONE`, `DNS_RESOURCE_GROUP`, `KEY_VAULT_URL`, `ESO_CLIENT_ID`, `EXTERNAL_DNS_CLIENT_ID`.
  Comptes de service attendus par les credentials fédérés (`namespace:nom`) : `external-secrets:external-secrets`, `external-dns:external-dns`.

- [ ] **Step 1:** `workload-identities.tf` : `azurerm_federated_identity_credential` en `for_each` sur `local.lz_aks.workload_identities` (via `nonsensitive(keys(...))` pour itérer), `issuer = azurerm_kubernetes_cluster.main.oidc_issuer_url`, `audience = ["api://AzureADTokenExchange"]`, subject `system:serviceaccount:<ns>:<sa>` selon une map locale `{ external_secrets = "external-secrets:external-secrets", external_dns = "external-dns:external-dns" }`. Le provider pointe déjà sur la subscription lz-aks.
- [ ] **Step 2:** `locals.tf` : `flux_substitutions = sensitive({ ...les 7 clés ci-dessus... })`.
- [ ] **Step 3:** `gitops.tf` :
  - `azurerm_kubernetes_cluster_extension.flux` : `name = "flux"`, `extension_type = "microsoft.flux"`.
  - `azurerm_kubernetes_flux_configuration.platform` : `name = "platform"`, `namespace = "flux-system"`, `scope = "cluster"`, `git_repository { url = var.gitops_repository_url, reference_type = "branch", reference_value = var.gitops_branch }`, `depends_on = [azurerm_kubernetes_cluster_extension.flux]`.
  - Trois `kustomizations` : `infra-controllers` (`./gitops/infrastructure/controllers`), `infra-configs` (`./gitops/infrastructure/configs`, `depends_on = ["infra-controllers"]`), `apps` (`./gitops/apps`, `depends_on = ["infra-configs"]`) ; toutes `wait = true`, `garbage_collection_enabled = true`, `post_build { substitute = local.flux_substitutions }`.
  - Variables `gitops_repository_url` (défaut `https://github.com/kjourdan1/azure-platform`) et `gitops_branch` (défaut `main`).
  - Commentaires : pourquoi l'extension plutôt que `flux bootstrap` (aucun jeton GitHub), pourquoi trois niveaux.
- [ ] **Step 4:** Vérifier validate + tflint comme Task 2 step 6 (dans `infra/aks`). Checkov si disponible ; toute alerte sur l'extension ou la config Flux est corrigée ou justifiée en `#checkov:skip`.
- [ ] **Step 5 (Review Focus 1):** Vérifier par lecture que chaque valeur de `flux_substitutions` est sous `sensitive()` et que les outputs Task 2 contenant des IDs sont `sensitive = true` ; le plan de la PR doit afficher `(sensitive value)`.
- [ ] **Step 6:** README `infra/aks` : décisions (B4ms et coût ≈ 0,20–0,25 €/h, KEDA add-on, extension Flux, substitution), mise à jour de « Installation » (Flux converge après `lab-up`, `kubectl get kustomizations -A`).
- [ ] **Step 7:** Commit `feat(aks): nœud B4ms, KEDA, extension Flux branchée sur gitops/`.

### Task 4: Squelette `gitops/` et validation en CI

**Files:**
- Create : `gitops/infrastructure/controllers/kustomization.yaml`, `gitops/infrastructure/configs/kustomization.yaml`, `gitops/infrastructure/configs/cluster-info.yaml`, `gitops/apps/kustomization.yaml`, `gitops/README.md`, `scripts/check-substitutions.sh`, `.github/workflows/gitops-pr.yml`

**Interfaces:**
- Consumes : la liste des 7 variables de Task 3 (source de vérité : clés de `flux_substitutions` dans `infra/aks/locals.tf`).
- Produces : `ConfigMap flux-system/cluster-info` (clé `dnsZone: ${DNS_ZONE}`), preuve visible après `lab-up` que la substitution fonctionne ; arborescence étendue par les PR 2 à 5.

- [ ] **Step 1 (test, Review Focus 4):** `scripts/check-substitutions.sh` : extrait les `${VAR}` de `gitops/**/*.yaml` et les clés de `flux_substitutions` dans `infra/aks/locals.tf`, sort en code 1 en listant les variables inconnues. Le lancer avec un `${UNKNOWN_VAR}` temporaire dans `cluster-info.yaml` : attendu exit 1 et `UNKNOWN_VAR` affiché.
- [ ] **Step 2:** Retirer la variable temporaire ; relancer : exit 0.
- [ ] **Step 3:** `kustomization.yaml` des trois racines (`resources: []` pour controllers et apps, `[cluster-info.yaml]` pour configs) ; `gitops/README.md` : rôle de chaque niveau, ordre, variables disponibles.
- [ ] **Step 4:** `gitops-pr.yml` : déclenché sur PR touchant `gitops/**`, `charts/**`, `scripts/check-substitutions.sh`, `infra/aks/locals.tf` ou le workflow ; `permissions: contents: read` ; actions épinglées par SHA comme les autres workflows ; jobs : `check-substitutions`, puis pour chaque racine `kustomize build` | `kubeconform -strict -summary` (`-ignore-missing-schemas` jusqu'à l'ajout des schémas de CRD en PR 2). Binaires kustomize et kubeconform téléchargés en version épinglée avec vérification sha256.
- [ ] **Step 5:** Exécuter localement les mêmes commandes (binaires dans le scratchpad) : `kustomize build` OK sur les trois racines, kubeconform `Valid: 1` pour configs.
- [ ] **Step 6:** Commit `feat(gitops): squelette Flux à trois niveaux et validation sur PR`.

### Task 5: Récit et apprentissage

**Files:**
- Modify : `README.md` (tableau des couches, roadmap, décisions), `docs/apprentissage.md` (session « GitOps avec Flux : socle »)

- [ ] **Step 1:** README racine : ligne `gitops/` dans le tableau, sous-zone DNS et identités dans la ligne `lz-aks`, Argo CD et `flux bootstrap` dans « Key decisions and alternatives rejected ».
- [ ] **Step 2:** Session d'apprentissage, cases non cochées : réconciliation (état désiré vs réel), Kustomization Flux vs `kustomization.yaml` Kustomize, `depends_on`/`wait`, post-build substitution, Workload Identity (émetteur OIDC, subject `system:serviceaccount:…`, pourquoi les credentials fédérés sont éphémères), extension gérée vs bootstrap.
- [ ] **Step 3:** Commit `docs: README et session d'apprentissage du socle GitOps`.
- [ ] **Step 4:** Push de la branche de travail, ouvrir la PR avec description pédagogique (ce que fait chaque fichier, pourquoi, quoi vérifier après merge).

### Vérification post-merge (par l'auteur, guidée dans la PR)

1. Merge → apply `landing-zone`, `platform`, `lz-aks` (approbation `prd`).
2. Délégation NS chez IONOS ; `dig +short NS lab.killianjourdan.com` renvoie les 4 serveurs Azure.
3. `lab-up` → `kubectl get kustomizations -n flux-system` : trois `Ready=True` ; `kubectl get cm cluster-info -n flux-system -o jsonpath='{.data.dnsZone}'` → `lab.killianjourdan.com`.
4. Après un `lab-down`, second `lab-up` : apply sans erreur (Review Focus 2).

---

## PR suivantes (esquisse, plan détaillé à rédiger après chaque merge)

- **PR 2 — Entrée et secrets** : HelmRelease cert-manager (support Gateway API), Envoy Gateway, external-dns (source `gateway-httproute`, provider azure, Workload Identity), ESO ; configs : `ClusterIssuer` prod + staging, `Gateway` 80/443, `ClusterSecretStore` Key Vault, générateurs `Password` + `PushSecret` `IfNotExists`. Attention : la policy ALZ `Enforce-GR-KeyVault` exige une date d'expiration et un `content_type` sur chaque secret ; vérifier que le provider Azure de `PushSecret` sait les poser, sinon exemption ciblée justifiée. Schémas CRD pour kubeconform. Démo : page de test HTTPS sur `hello.lab…`.
- **PR 3 — Chart et boutique** : `charts/aks-store` dérivé de l'upstream (MIT, attribution), `existingSecret`, `ClusterIP`, `HTTPRoute` store-front seulement, `securityContext`, images épinglées, sans `ai-service` ; `helm lint`/`helm template` en CI ; HelmRelease + `ExternalSecret` dans `gitops/apps/store`.
- **PR 4 — Observabilité et scaling** : kube-prometheus-stack (rétention courte, `grafana.lab…`, mot de passe via ESO), `ServiceMonitor` RabbitMQ, `ScaledObject` KEDA sur la file `orders`, tableau de bord ; vérification policies ALZ (node-exporter).
- **PR 5 — Gouvernance** : Kyverno, policies (limites, pas de `latest`, registres, `runAsNonRoot` en audit, génération NetworkPolicy deny-all), NetworkPolicies du chart, `kyverno test` en CI.
- **PR 6 — Récit** : README racine et de couche finalisés, roadmap à jour.

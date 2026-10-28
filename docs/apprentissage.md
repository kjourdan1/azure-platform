# Apprentissage

Une checklist par session. Un point n'est coché que lorsqu'il a été démontré (quiz réussi,
commande lue, plan expliqué), pas seulement lu.

## Session 1 — Bootstrap : state distant et identités CI

### Le problème
- [x] Pourquoi un state distant : source de vérité partagée poste/CI, contient des valeurs sensibles en clair
- [x] Pourquoi un verrou : sans lui, deux `apply` concurrents → le dernier à écrire écrase le state, ressources orphelines dans Azure
- [ ] Le problème de la poule et de l'œuf : où stocker le state du code qui crée le stockage du state

### La solution
- [x] OIDC : GitHub signe un JWT, Entra vérifie émetteur + `sub` + `aud`, aucun secret stocké
- [x] Deux identités : c'est le `sub` du jeton (`pull_request` vs `environment:prd`) qui empêche une PR d'obtenir l'identité `apply`
- [ ] `plan` exécute du code (`data "external"`, providers) → identité `plan` en lecture seule
- [ ] Storage Account sans clé : `shared_access_key_enabled = false` + `storage_use_azuread = true`
- [x] Management plane (`actions`) vs data plane (`dataActions`) : Owner n'a aucune dataAction, mais `listKeys` lui ouvrait les données tant que les clés existaient → désactiver les clés ferme ce contournement
- [x] Global Admin est un rôle Entra, pas Azure RBAC : aucun droit sur les ressources
- [ ] Conteneur via `storage_account_id` = management plane, role assignment = data plane
- [x] `prevent_destroy` sur le compte de state : un renommage fait échouer le plan au lieu de détruire le compte (ne protège pas d'une suppression hors Terraform → resource lock)
- [ ] azurerm 5.x : `resource_providers_to_register` explicite
- [x] Migration local → distant (`terraform init -migrate-state`) exécutée, vérifiée par un plan « No changes »
- [x] MFA obligatoire sur ARM : c'est le claim `amr` du jeton qui compte, pas les méthodes enregistrées sur le compte

### Le contexte large
- [x] Comparaison avec l'existant en entreprise : SPN + certificat PFX vs OIDC, state créé en CLI vs bootstrap versionné
- [ ] Limite assumée : endpoint public tant que runners GitHub hébergés ; cible runner self-hosted à IP fixe (risque des runners self-hosted sur dépôt public)

## Session 2 — Socle GitOps (1/2) : DNS et identités des contrôleurs

### Le problème
- [ ] Pourquoi l'IP publique de la boutique change à chaque `lab-up`, et pourquoi il faut donc un outil (external-dns) qui écrit le DNS tout seul
- [ ] Pourquoi un contrôleur dans le cluster a besoin d'une identité Azure, et pourquoi pas une clé API stockée

### La solution
- [ ] Délégation DNS : un enregistrement NS chez le parent (IONOS) confie la sous-zone `lab` à d'autres serveurs (Azure DNS) ; le parent ne répond plus pour `*.lab`
- [ ] Moindre privilège par portée : *DNS Zone Contributor* sur la sous-zone seule, pas sur le domaine ni la subscription
- [ ] Workload Identity : identité managée + credential fédéré (émetteur OIDC du cluster + `system:serviceaccount:<ns>:<sa>`) ; même mécanique que l'OIDC GitHub de la session 1
- [ ] Pourquoi l'identité est permanente mais son credential fédéré éphémère : l'URL de l'émetteur OIDC change à chaque création de cluster
- [ ] Secrets Officer vs Secrets User : ESO doit créer les mots de passe absents pour qu'ils ne passent jamais par le state Terraform

### Le contexte large
- [ ] Découpage des PR par couche : un output n'existe dans le state qu'après l'apply, d'où lz-aks avant aks

## Session 3 — Socle GitOps (2/2) : Flux branché sur le dépôt

### Le problème
- [ ] Pourquoi un cluster détruit chaque soir rend le GitOps indispensable (et pas juste pratique)
- [ ] Réconciliation : Flux compare en continu l'état désiré (Git) et l'état réel (cluster), et corrige l'écart ; ce que ça change par rapport à un `kubectl apply` en CI

### La solution
- [ ] Extension AKS vs `flux bootstrap` : qui installe Flux, et pourquoi le bootstrap aurait demandé un jeton GitHub en écriture
- [ ] `GitRepository` (où lire) vs `Kustomization` Flux (quoi appliquer, dans quel ordre) vs `kustomization.yaml` Kustomize (comment assembler les fichiers) : trois objets qui portent presque le même nom
- [ ] `depends_on` + `wait` : pourquoi un `ClusterIssuer` échouerait avant que cert-manager ait installé sa CRD
- [ ] `garbage_collection_enabled` : supprimer un fichier de Git supprime l'objet du cluster
- [ ] Post-build substitution : d'où viennent les `${VAR}`, et pourquoi une variable inconnue devient une chaîne vide sans erreur
- [ ] Credentials fédérés éphémères : recréés à chaque `lab-up` avec la nouvelle URL d'émetteur OIDC
- [ ] KEDA en add-on : ce qu'AKS installe, et ce qu'il restera à déclarer (`ScaledObject`)
- [ ] Lire le plan : le contenu des Kustomizations est masqué parce que la map de substitution est sensible

### Le contexte large
- [ ] Les trois filtres d'une taille de VM : policy FinOps, offre AKS de la région, quota de vCPU par famille ; lire `az vm list-usage` et l'activity log d'un cluster bloqué en « Creating »
- [ ] Ce que coûte le D4as_v7 par heure, et pourquoi `lab-down` reste la vraie garantie de budget
- [ ] Vérifier une convergence avec les outils : `kubectl get kustomizations -n flux-system`, `kubectl describe kustomization`, events

## Session 4 — Entrée HTTPS et chemin d'un secret

### Le problème
- [ ] Pourquoi une IP qui change à chaque `lab-up` impose external-dns, et un certificat renouvelé impose cert-manager
- [ ] Ce que Gatekeeper (policies ALZ) refuse dans le cluster, et pourquoi un chart « standard » peut être bloqué à l'admission

### La solution
- [ ] Gateway API : GatewayClass (qui implémente), Gateway (le point d'entrée, ses listeners), HTTPRoute (qui reçoit quoi) ; pourquoi c'est le successeur d'Ingress
- [ ] HTTP-01 : Let's Encrypt appelle `http://hello.lab…/.well-known/acme-challenge/…` ; pourquoi la route de redirection HTTPS ne l'intercepte pas (priorité de la route la plus spécifique)
- [ ] Pourquoi cert-manager dépend d'Envoy Gateway (`dependsOn` d'une HelmRelease vs `depends_on` d'une Kustomization)
- [ ] Workload Identity côté pod : annotation `client-id` sur le compte de service, label `azure.workload.identity/use`, jeton projeté, credential fédéré qui fait la correspondance
- [ ] Le chemin d'un secret : générateur → PushSecret → Key Vault → ExternalSecret → Secret → variable d'environnement ; pourquoi l'application lit le Secret relu depuis Key Vault et pas la graine
- [ ] Policies Key Vault en Deny : `contentType` et validité ≤ 90 jours ; d'où vient `${SECRET_EXPIRES_AT}` et pourquoi `time_rotating` plutôt qu'un horodatage
- [ ] `policy: sync` et registre TXT d'external-dns : ce qu'il a le droit de supprimer

### Le contexte large
- [ ] Limite Let's Encrypt de 5 certificats identiques par semaine, et quand passer sur staging
- [ ] Risque de reprise de sous-domaine avec des enregistrements DNS orphelins
- [ ] Pourquoi l'identité `plan` a besoin du Cluster User Role, et pourquoi ce rôle ne donne aucun accès aux objets du cluster

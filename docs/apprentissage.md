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

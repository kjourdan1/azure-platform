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
- [ ] `prevent_destroy` sur le compte de state
- [ ] azurerm 5.x : `resource_providers_to_register` explicite
- [ ] Migration local → distant (`terraform init -migrate-state`) lue et exécutée

### Le contexte large
- [x] Comparaison avec l'existant en entreprise : SPN + certificat PFX vs OIDC, state créé en CLI vs bootstrap versionné
- [ ] Limite assumée : endpoint public tant que runners GitHub hébergés ; cible runner self-hosted à IP fixe (risque des runners self-hosted sur dépôt public)

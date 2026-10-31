# Reprise brownfield : intégrer la subscription LAB dans la landing zone

Runbook d'une reprise réelle, exécutée sur cette plateforme. Il sert de modèle pour une
mission client : faire évoluer une landing zone « Start Small » vers Enterprise Scale en y
intégrant l'existant, sans recréer ni interrompre ce qui tourne.

## Situation de départ (inventaire du 2026-10-30)

| Constat | Détail |
|---|---|
| Subscription `LAB` hors hiérarchie | Rattachée au Tenant Root Group : aucune policy ALZ, seule l'initiative par défaut de Defender |
| Contenu mixte | Socle Terraform (state, identités CI : gérés par `infra/bootstrap`) **et** une charge de travail en production : `rg-portfolio` / Static Web App `portfolio-kj`, servant `www.killianjourdan.com`, créée hors code, sans aucun tag |
| Defender for Cloud | Plan Defender CSPM (`CloudPosture`) activé hors code, facturé 0,64 € en octobre, puis désactivé à la main le 26 |
| Dérive du bootstrap | Budget global, alerte d'anomalie de coût, gestion GitHub et rôles `apply_subscription` présents dans le code mais jamais appliqués |
| Hiérarchie ALZ | `management`, `connectivity`, `identity` vides ; `azpl-platform` rattachée directement à `platform` |

Risque principal : rattacher `LAB` tel quel à la hiérarchie applique les policies `Deny` du
management group `alz`, dont `azpl-rg-tag-owner` / `azpl-rg-tag-cost-center`. `rg-portfolio`
deviendrait non conforme et toute modification du site serait refusée.

## Cible

| Élément | Cible | Pourquoi |
|---|---|---|
| `LAB` | management group `management` | Ne porte que le plan de gestion (state, identités CI) |
| Portfolio | subscription `azpl-lz-web`, management group `online` | Charge de travail publique : une landing zone, pas la subscription du state |
| Static Web App | importée dans Terraform (`infra/lz-web`), taguée | Plus aucune ressource hors code |
| Defender CSPM | niveau gratuit fixé en code | Non exploité : décision FinOps documentée, toute réactivation devient une dérive visible |
| Bootstrap | code aligné sur la réalité, budget et alerte d'anomalie appliqués | Fin de la dérive |

## Principes

1. **Mesurer avant d'imposer** : inventaire et conformité avant chaque bascule.
2. **Aucune recréation** : on déplace et on importe. Un plan qui veut recréer une ressource
   existante est un échec de la reprise, pas un détail.
3. **Chaque étape est réversible** et a son critère de succès vérifiable.
4. **Séparation des droits conservée** : la CI n'écrit jamais dans `LAB` ; ce qui touche `LAB`
   passe par l'opérateur (Cloud Shell), avec un plan relu.

## Étapes

| # | Étape | Qui | Critère de succès | Retour arrière |
|---|---|---|---|---|
| 0 | Inventaire et état de conformité de référence (`scripts/inventory/*.kql`) | Opérateur ou CI en lecture | Liste des ressources hors code, sans tags, par subscription | — |
| 1 | Créer `azpl-lz-web` sous `online` (alias, PR B1) | CI | Subscription active, rattachée à `online` | Annuler la subscription |
| 2 | Gouverner `azpl-lz-web` (vending : tags, budget, providers dont `Microsoft.Web`), retirer l'alias du state (PR B2) | CI | Plan suivant « No changes » | Revert de la PR |
| 3 | Resource group cible `rg-azpl-web-prd-frc-001` (couche `infra/lz-web`, PR B3) | CI | RG créé, tagué, conforme | Revert de la PR |
| 4 | Déplacement à blanc (`validateMoveResources`) | Opérateur | Réponse sans erreur | — |
| 5 | Déplacement de la Static Web App | Opérateur | Contrôles ci-dessous tous verts | Déplacement inverse vers `rg-portfolio` |
| 6 | Import de la Static Web App et de son domaine dans `infra/lz-web` (PR B4) | CI | Plan : import, aucune recréation ; seuls les tags changent | Retrait des blocs `import` |
| 7 | **Revue des droits** : retirer à l'identité `apply` l'Owner implicite sur les management groups | Opérateur (Cloud Shell) | Plus aucun Owner de `apply` sur un management group ; Owner conservé sur ses subscriptions | Réattribuer Owner sur les management groups |
| 8 | Bootstrap (PR B5) : `LAB` rattachée à `management` et renommée `azpl-management`, Defender CSPM fixé au niveau gratuit, budget global, alerte d'anomalie, code aligné sur la réalité | Opérateur (Cloud Shell) | Plan complet `5 to add, 0 to change, 0 to destroy`, puis « No changes » ; `apply` sans aucun rôle hérité sur la subscription du state | Revert, apply ; rattachement inverse |
| 9 | Clôture : inventaire de fin, suppression de `rg-portfolio` vide | Opérateur | Zéro ressource hors code | — |

### Étape 4 : déplacement à blanc

```bash
SRC=/subscriptions/<id LAB>/resourceGroups/rg-portfolio
SWA=$SRC/providers/Microsoft.Web/staticSites/portfolio-kj
DST=/subscriptions/<id azpl-lz-web>/resourceGroups/rg-azpl-web-prd-frc-001
az resource invoke-action --action validateMoveResources --ids "$SRC" \
  --request-body "{\"resources\": [\"$SWA\"], \"targetResourceGroup\": \"$DST\"}"
```

Prérequis vérifiés : même tenant, `Microsoft.Web` enregistré dans la subscription cible, droit
`resourceGroups/moveResources/action` sur la source et `resourceGroups/write` sur la cible, aucun
verrou en lecture seule.

### Étape 5 : déplacement et contrôles

Relever avant : nom d'hôte par défaut, état du domaine `www.killianjourdan.com`, dernier
déploiement réussi.

```bash
az resource move --ids "$SWA" --destination-group rg-azpl-web-prd-frc-001 \
  --destination-subscription-id <id azpl-lz-web>
```

Pendant le déplacement, les deux resource groups sont verrouillés en écriture ; la ressource
reste servie. Après :

| Contrôle | Commande | Attendu |
|---|---|---|
| Site par défaut | `curl -sI https://<hostname>.azurestaticapps.net` | 200 |
| Domaine personnalisé | `curl -sI https://www.killianjourdan.com` | 200, certificat valide |
| État du domaine | `az staticwebapp hostname list -n portfolio-kj -g rg-azpl-web-prd-frc-001` | `Ready` |
| Déploiement | relancer le workflow de déploiement du dépôt `portfolio-kj` | succès (jeton de déploiement inchangé) |

Microsoft documente le déplacement des Static Web Apps entre subscriptions, mais pas la
conservation du domaine personnalisé ni du jeton de déploiement : ce sont les points de
contrôle de cette étape. En cas d'échec, déplacement inverse vers `rg-portfolio`.

Les attributions de rôles ne suivent pas une ressource déplacée : aucune n'existe sur ce site.

### Étape 7 : revue des droits avant de rattacher la subscription du state

L'inventaire des droits de l'identité `apply` a révélé un **Owner direct sur les 12
management groups** de la hiérarchie ALZ, absent de tout code : Azure attribue Owner au
créateur d'un management group, et c'est `apply` qui a créé la hiérarchie. Rattacher la
subscription du state à `management` l'en aurait rendue Owner par héritage, à rebours de la
séparation des droits (la CI n'écrit jamais dans le state).

Ces attributions ne servent à rien : `apply` agit par Management Group Contributor, Resource
Policy Contributor et User Access Administrator à la racine, et par Owner sur les
subscriptions qu'elle a créées. Elles sont retirées avant le rattachement :

```bash
P=$(az identity show -g rg-azpl-identity-prd-frc-001 -n id-azpl-apply-prd-frc-001 \
  --subscription <id LAB> --query principalId -o tsv)
OWNER=8e3af657-a8ff-443c-a75c-2fe8c4bcb635
for mg in alz platform management connectivity identity security landingzones online corp local sandbox decommissioned; do
  for id in $(az rest --method get \
      --url "https://management.azure.com/providers/Microsoft.Management/managementGroups/$mg/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=assignedTo('$P')" \
      --query "value[?properties.scope=='/providers/Microsoft.Management/managementGroups/$mg' && ends_with(properties.roleDefinitionId, '$OWNER')].id" -o tsv); do
    az role assignment delete --ids "$id"
  done
done
```

`az role assignment list --assignee <id> --all` ne remonte ni les attributions directes sur
les management groups ni l'Owner obtenu par création d'alias : le listing paraît propre alors
que les droits existent. On liste et on supprime par l'API REST (`$filter=assignedTo(...)` à
chaque scope). Les suppressions mettent quelques secondes à se propager : une vérification
immédiate peut encore les montrer.

Reste ouvert : User Access Administrator à la racine permet encore à `apply` de s'attribuer un
rôle. Cible : Role Based Access Control Administrator avec une condition ABAC qui limite les
rôles et les principaux qu'elle peut attribuer.

### Étape 8 : rattacher la subscription du state

Avant : lister les affectations `Deny` héritées par `management` (depuis `alz` et `platform`) et
les confronter aux ressources restantes de `LAB` (state et identités, tous tagués).
Après : `az policy state trigger-scan --subscription <id LAB>` puis comparaison avec l'état de
référence de l'étape 0.

### Étape 8 : prérequis du plan des PR

Le budget global vit sur le profil de facturation : le plan des PR qui touchent le bootstrap
doit pouvoir le lire. Rôle « Billing profile reader » pour l'identité `plan`, attribué par
l'API (le portail n'attribue pas de rôle de facturation à une identité managée) :

```bash
BP=/providers/Microsoft.Billing/billingAccounts/<compte>/billingProfiles/<profil>
az rest --method put \
  --url "https://management.azure.com$BP/billingRoleAssignments/$(uuidgen)?api-version=2024-04-01" \
  --body "{\"properties\":{\"principalId\":\"<principalId plan>\",\"principalTenantId\":\"<tenant>\",\"roleDefinitionId\":\"$BP/billingRoleDefinitions/40000000-aaaa-bbbb-cccc-100000000002\"}}"
```

La CI reçoit aussi `platform_subscription_ids` (secret `PLATFORM_SUBSCRIPTION_IDS`) : sans
lui, le plan proposait de détruire les rôles AKS de l'identité `plan`.

## Journal d'exécution

| Étape | Date | Résultat |
|---|---|---|
| 0. Inventaire | 2026-10-30 | `LAB` sous Tenant Root Group ; 1 resource group sans tags (`rg-portfolio`), 1 ressource hors code (`portfolio-kj`, West Europe) |
| 1. `azpl-lz-web` créée | 2026-10-30 | Plan `1 to add` ; subscription active sous `online` |
| 2. Gouvernance | 2026-10-30 | Plan `19 to add, 0 to destroy`, alias oublié sans destruction ; un plantage passager du provider `alz` en CI, non reproduit en local, relancé une fois |
| 3. RG d'accueil | 2026-10-30 | Plan `1 to add` ; `Microsoft.Web` enregistré |
| 4. Déplacement à blanc | 2026-10-30 | `validateMoveResources` : `{}`, aucun obstacle |
| 5. Déplacement | 2026-10-30 | Nom d'hôte, SKU, région, `www` (`Ready`, HTTP 200) identiques avant et après ; apex `Failed` avant comme après (préexistant) |
| 6. Import | 2026-10-30 | Plan `2 to import, 1 to add, 0 to change, 0 to destroy`. Imports réussis ; la pose des tags échoue (`Resource already exists` : `tags/default` existe toujours). Corrigé par `azapi_update_resource` ; plan suivant `1 to add, 0 to change`, imports sans écart |

## Leçons à reporter en mission

- Une subscription « isolée » mélange presque toujours socle et charge de travail : séparer
  avant de gouverner, sinon les policies bloquent la production.
- Un rattachement de management group est une action instantanée et lourde : il se prépare
  comme une mise en production (inventaire, conformité, retour arrière).
- `import` déclaratif et plan relu en PR : la preuve qu'une reprise ne recrée rien.
- Importer sans tout réécrire : un provider qui envoie le corps complet (azapi) supprime ce
  qu'on ne déclare pas. Reproduire l'existant, puis mettre en conformité par l'API Tags.
- L'API Tags d'ARM expose une sous-ressource `tags/default` qui existe toujours : on la met à
  jour (`azapi_update_resource`), on ne la crée pas.
- Un provider qui lit des secrets au refresh (clé de déploiement d'une Static Web App avec
  azurerm) impose de donner ce droit au plan des PR : en choisir un autre plutôt que d'élargir.
- Les droits d'une identité de CI peuvent venir d'ailleurs que du code qui les déclare : ici,
  `apply` est Owner des subscriptions qu'elle a créées par alias. L'inventaire des droits
  fait partie de la reprise.

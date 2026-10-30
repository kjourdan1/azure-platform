# Reprise brownfield : intégrer la subscription LAB dans la landing zone

Runbook d'une reprise réelle, exécutée sur cette plateforme. Il sert de modèle pour une
mission client : faire évoluer une landing zone « Start Small » vers Enterprise Scale en y
intégrant l'existant, sans recréer ni interrompre ce qui tourne.

## Situation de départ (inventaire du 2026-10-30)

| Constat | Détail |
|---|---|
| Subscription `LAB` hors hiérarchie | Rattachée au Tenant Root Group : aucune policy ALZ, seule l'initiative par défaut de Defender |
| Contenu mixte | Socle Terraform (state, identités CI : gérés par `infra/bootstrap`) **et** une charge de travail en production : `rg-portfolio` / Static Web App `portfolio-kj`, servant `www.killianjourdan.com`, créée hors code, sans aucun tag |
| Defender for Cloud | Plans `Discovery` et `FoundationalCspm` au niveau payant, activés hors code (0,64 € en octobre) |
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
| Defender `Discovery` | désactivé en code | Non exploité : décision FinOps documentée |
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
| 7 | Rattacher `LAB` à `management` (PR B5) | CI | Conformité de `LAB` inchangée après scan | Rattachement inverse |
| 8 | Réconcilier le bootstrap : `Discovery` désactivé, budget global, alerte d'anomalie, code aligné (PR B6) | Opérateur (Cloud Shell) | Plan relu sans destruction, puis « No changes » | Revert, apply |
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

### Étape 7 : rattacher LAB

Avant : lister les affectations `Deny` héritées par `management` (depuis `alz` et `platform`) et
les confronter aux ressources restantes de `LAB` (state et identités, tous tagués).
Après : `az policy state trigger-scan --subscription <id LAB>` puis comparaison avec l'état de
référence de l'étape 0.

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

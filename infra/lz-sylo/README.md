# lz-sylo

## Problème résolu
Socle de la landing zone `azpl-lz-sylo` (management group `online`) qui héberge l'application
Sylo : réseau, secrets, images et identités, séparés des charges applicatives (`infra/sylo`).

## Approche retenue
Resource group, VNet spoke avec deux sous-réseaux délégués (`snet-aca` /27, `snet-pg` /28), zone
DNS privée PostgreSQL, Log Analytics, Key Vault (RBAC), ACR Basic et une identité managée par
charge (api, web, n8n) avec AcrPull, plus lecture des secrets pour api et n8n.

## Décisions et alternatives écartées
- **Pas d'appairage au hub** : la stack `platform` n'est pas encore appliquée dans le tenant Sylo.
  À ajouter avec elle ; aucun coût fixe d'ici là (Firewall, NAT Gateway interdits par policy).
- **Log Analytics propre** plutôt que le central de `platform` : même raison, rétention 30 jours,
  quota de 0,5 Go par jour pour tenir le budget de 75 €/mois (ADR-027).
- **Key Vault et ACR en accès public** (auth Entra uniquement) : pas de private endpoint au MVP,
  coût fixe évité (ADR-010). Dérogations Checkov documentées dans le code.

## Limites connues
- La subscription `azpl-lz-sylo` est créée à la main dans le portail ; l'identité apply doit y
  avoir Contributor et User Access Administrator (à donner une fois par le propriétaire).
- Ordre d'apply : landing-zone, puis lz-sylo, puis sylo.
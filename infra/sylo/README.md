# sylo

## Problème résolu
Déploie l'application Sylo sur Azure Container Apps avec sa base et son stockage (ADR-010,
ADR-024, ADR-027).

## Approche retenue
Environnement Container Apps (profil Consumption) intégré au VNet de `lz-sylo`, trois
applications (`ca-sylo-api`, `ca-sylo-web`, `ca-sylo-n8n`), PostgreSQL Flexible Server 16
Burstable B1ms en accès privé (bases `sylo` et `n8n`), Storage Account (blob `audio` avec cycle de
vie de 30 jours, queue `agent-events`).

## Décisions et alternatives écartées
- **Terraform ignore l'image et le port** des conteneurs (ADR-011) : la CI applicative Azure
  DevOps publie les révisions. Image de démarrage : `quickstart`, port 80.
- **n8n** : réplica permanent (ADR-027), rôle PostgreSQL `n8n` à mot de passe sans droit sur la
  base `sylo` ; son mot de passe est généré hors Terraform et stocké dans le Key Vault.
- **API et jobs** : authentification Entra uniquement, l'identité de l'API est administrateur
  Entra du serveur.

- **n8n déployé par tag** : `n8n_image_tag` vide = image de démarrage, rien ne change. Renseigné
  (image `docker.n8n.io/n8nio/n8n`), n8n lit ses secrets dans le Key Vault (`n8n-db-password`,
  `n8n-encryption-key`, `qonto-api-login`, `qonto-api-secret`) et se connecte à sa base. L'interface
  reste interne tant que `entra_n8n_client_id` (application Entra `sylo-n8n-web`) est vide.

## Limites connues
- Domaines personnalisés (`app.sylo.sh`, `api.sylo.sh`) et pare-feu du storage (IP du VPS,
  ADR-025) : à ajouter dans une étape suivante.
- Mot de passe administrateur PostgreSQL généré par Terraform, donc présent dans le state (privé,
  accès Entra) ; jamais utilisé par une charge.
- Estimation ≈ 35 à 55 €/mois (ADR-027), à confirmer par la calculatrice Azure.
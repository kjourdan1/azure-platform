# IA — fondations Azure AI Foundry

## Problème résolu
Donner à la plateforme un socle IA gouverné, sur lequel les applications (le cluster AKS,
puis un assistant d'entreprise) consomment des modèles sans clé d'API, avec une facture
bornée, des données traitées dans l'UE et une traçabilité de chaque appel.

## Approche retenue
Couche permanente dans la subscription `azpl-lz-aks`, resource group dédié :

| Ressource | Rôle |
|---|---|
| Compte Foundry (`AIServices`, gestion de projets) | Modèles, projets, agents et évaluations sous une seule identité |
| Projet `azure-platform` | Espace de travail des applications de la plateforme |
| Déploiement `gpt-5.4-mini` (Data Zone Standard, UE) | Modèle de conversation, version épinglée, plafonné à 10 000 tokens/minute |
| Paramètre de diagnostic → Log Analytics central | Requêtes, audit, consommation de tokens |
| Identité `ai-smoke` | Appeler le modèle depuis le workflow `ai-smoke`, rien d'autre |

## Décisions et alternatives écartées
- **Nouveau modèle Foundry (compte + projets) plutôt que le hub** : le hub exige Storage
  Account et Key Vault dédiés ; le compte `AIServices` porte directement modèles, projets et
  agents. C'est la direction de Microsoft.
- **Aucune clé** (`local_auth_enabled = false`) : authentification Entra ID uniquement, comme
  tout le dépôt. Les applications passeront par Workload Identity, la CI par OIDC.
- **Data Zone Standard** plutôt que Global Standard : le traitement reste dans la zone UE,
  exigence fréquente des clients français, au même modèle de facturation au token.
- **Coût fixe nul, couche permanente** : compte, projet et déploiement Standard ne coûtent
  rien sans appel. Le plafond de capacité (10K TPM) borne la consommation, le budget de la
  subscription alerte au-delà. Un déploiement provisionné (PTU) serait facturé à l'heure.
- **Version épinglée, sans mise à jour automatique** : changer de modèle passe par une PR et
  son plan. Retrait annoncé de `gpt-5.4-mini 2026-03-17` : 2027-09-21.
- **Subscription partagée avec le cluster** : une subscription IA dédiée (vending) est la cible ;
  écartée pour l'instant car une subscription neuve repart sans quota de modèles.
- **Policy `Enforce-GR-OpenAI` de la landing zone** : en `DoNotEnforce`, évaluée sans bloquer.

## Limites connues
- **Endpoint public**, protégé par Entra ID : les runners GitHub hébergés ne peuvent pas joindre
  un private endpoint. Cible : runner self-hosted dans le VNet, private endpoint dans le spoke,
  zones DNS privées (`privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com`,
  `privatelink.services.ai.azure.com`) dans le hub.
- **Accès sortant non restreint** : les agents à venir appelleront des outils externes ; la
  liste blanche sera posée avec eux.
- **Chiffrement par clé Microsoft**, pas de clé client (CMK).

## Installation
PR → plan commenté → merge → `terraform-apply` avec approbation.
Puis copier `terraform output -raw smoke_client_id` dans le secret `AZURE_CLIENT_ID_AI_SMOKE`
de l'environnement GitHub `lab`, et lancer le workflow `ai-smoke` : le résumé du run montre la
réponse du modèle et les tokens consommés.

Utilisation interactive : portail Foundry (https://ai.azure.com), projet `azure-platform`.

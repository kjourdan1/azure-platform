# ai-gateway

Console de la plateforme servie par AKS : coût de tout le lab (facturé et en direct) et
assistant branché sur Azure AI Foundry, avec les tokens et le coût de chaque échange.

## Problème résolu
Foundry déployé ne prouve rien tant qu'une application ne le consomme pas. Et le coût d'un
lab se découvre d'habitude le lendemain, sur la facture. Cette console montre les deux au
même endroit : ce que coûte la plateforme maintenant, et ce que coûte chaque question
posée au modèle.

## Architecture

```
navigateur ──HTTPS──▶ Gateway Envoy (OIDC Entra ID, limite de débit)
                        ├─ /            ▶ web        nginx, fichiers statiques
                        ├─ /api/cost/*  ▶ cost-api   Cost Management, Resource Graph, Retail Prices
                        └─ /api/chat*   ▶ chat-api   Foundry (streaming) ──▶ cost-api (prix du modèle)
```

| Service | Rôle | Identité Azure (Workload Identity) |
|---|---|---|
| `web` | Page, CSS, JavaScript sans bibliothèque | aucune |
| `cost-api` | Coût facturé (Cost Management, 30 jours, par subscription et service) ; coût en direct (ressources en cours d'exécution × tarif public de l'heure) ; prix du modèle | `ai-cost` : Cost Management Reader et Reader sur le management group `alz` |
| `chat-api` | Conversation en streaming (SSE), tokens exacts en fin de réponse, coût de l'échange, cumuls | `ai-chat` : Cognitive Services OpenAI User sur le compte Foundry |

Un service par source de données et par identité : le service exposé au modèle n'a aucun
droit sur les coûts, et inversement. `chat-api` lit les prix du modèle chez `cost-api` par
le réseau du cluster ; s'il ne répond pas, le chat continue, sans coût affiché.

## Décisions
- **Deux coûts, libellés comme tels.** Cost Management publie avec 8 à 24 h de retard : le
  « facturé » est exact mais jamais en direct. Le « en direct » valorise ce qui tourne
  (Resource Graph) au tarif public (API Retail Prices), avec les compteurs de la facture
  réelle. Ce qui se facture à l'usage (tokens, logs, opérations) est listé, pas estimé.
- **Caches côté serveur** (15 min pour Cost Management, 60 s pour l'inventaire), un seul
  rafraîchissement à la fois : le nombre d'onglets ouverts ne change pas le nombre d'appels
  à Azure. Une panne amont sert la dernière valeur, signalée comme telle.
- **Tokens en direct** : chaque fragment streamé incrémente un compteur approché, remplacé
  par la consommation exacte que Foundry envoie en fin de réponse (`include_usage`).
- **Garde-fous du chat** : rôles `user`/`assistant` seulement (pas de prompt système fourni
  par le client), 4 000 caractères par message, 12 messages d'historique, 800 tokens de
  réponse, 4 conversations simultanées ; la Gateway ajoute l'authentification et la limite
  de débit, le quota du déploiement reste le plafond dur.
- **Images** : bases épinglées par digest, utilisateur numérique non root, système de
  fichiers en lecture seule, tag = commit. Tests, construction et scan Trivy sur chaque PR ;
  publication dans ACR depuis `main` seulement (`build-images.yml`).
- **Front sans framework** : HTML, CSS et JavaScript servis tels quels, CSP stricte
  (`'self'` uniquement), aucun contenu inséré en HTML.

## Développement
```bash
cd apps/ai-gateway/cost-api && python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest -q
```
`cost-api` fonctionne en local avec une session `az login` (DefaultAzureCredential) et un
rôle de lecture des coûts.

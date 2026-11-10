# ai-gateway — état et reprise

Console sur AKS : coût de tout le lab (facturé et en direct) et assistant branché sur
Foundry, avec les tokens et le coût de chaque échange. Trois microservices (`web`,
`cost-api`, `chat-api`) derrière la Gateway Envoy, authentification Entra ID (OIDC).
Architecture et décisions : `apps/ai-gateway/README.md`.

## État

Livré par quatre PR, toutes mergées le 2026-11-10 :

| PR | Contenu |
|---|---|
| kjourdan1/azure-platform#37 | Identités `ai-chat`, `ai-cost`, `build` (lz-aks) |
| kjourdan1/azure-platform#38 | Inférence Foundry pour `ai-chat` (infra/ai) |
| kjourdan1/azure-platform#39 | Application, tests, workflow `build-images`, images de base corrigées après le premier scan Trivy |
| kjourdan1/azure-platform#40 | Déploiement GitOps, OIDC Entra, limite de débit, NetworkPolicies ; images `f196e356bb96` épinglées par digest |

Prérequis manuels faits : secrets de dépôt `AZURE_CLIENT_ID_BUILD` et `AI_GATEWAY_CLIENT_ID`,
app registration `azpl-ai-gateway`, secret client dans Key Vault.

## Exploitation

### Mettre à jour les images
1. Merger le changement sous `apps/ai-gateway/` : `build-images` publie les images depuis `main`.
2. Reporter les trois digests du résumé du run dans `gitops/apps/ai-gateway/kustomization.yaml`,
   par PR. Le digest, pas le tag : un tag peut être réécrit dans le registre.

### Rotation du secret client (au plus tous les 85 jours)
Personne n'a d'accès permanent aux secrets du coffre : l'opérateur s'attribue le rôle le temps
du dépôt, puis le retire.

1. App registration `azpl-ai-gateway` → nouveau client secret (90 jours au plus).
2. Accès juste à temps :
   ```bash
   P=<object ID de l'opérateur>
   KV=$(az keyvault show -n kv-azpl-aks-prd-frc-001 --query id -o tsv)
   az role assignment create --assignee-object-id "$P" --assignee-principal-type User \
     --role "Key Vault Secrets Officer" --scope "$KV" --query id -o tsv
   ```
   Attendre une à deux minutes (propagation).
3. Saisie du secret, **seule sur sa ligne** (collée avec la commande suivante, `read` lirait
   la ligne d'après au lieu du secret) :
   ```bash
   read -rsp "Secret client : " S; echo; echo "longueur : ${#S}"
   ```
4. Dépôt (la policy exige `contentType` et une expiration) :
   ```bash
   az keyvault secret set --vault-name kv-azpl-aks-prd-frc-001 \
     --name ai-gateway-oidc-client-secret --content-type text/plain \
     --expires "$(date -u -d '+85 days' +%Y-%m-%dT%H:%M:%SZ)" --value "$S" --query id -o tsv
   unset S
   ```
5. Retrait du rôle : `az role assignment delete --assignee-object-id "$P" --role "Key Vault Secrets Officer" --scope "$KV"`.
6. Supprimer l'ancien secret dans l'app registration. External Secrets relit le coffre toutes
   les heures.

## Vérification après `lab-up`

Rien de ce qui suit n'a pu être testé hors cluster.

1. `kubectl get pods,httproute,securitypolicy,backendtrafficpolicy -n ai-gateway` : pods
   `Running`, policies `Accepted`.
2. `kubectl get externalsecret -n ai-gateway` : `SecretSynced`.
3. Navigation privée sur `https://ai.lab.killianjourdan.com` : redirection vers la connexion
   Microsoft ; un compte non assigné est refusé.
4. Console : coûts affichés (Workload Identity de `cost-api`), réponse du modèle en streaming
   avec tokens et coût (Workload Identity de `chat-api`).
5. Plus de 20 messages en une minute : réponse 429.
6. `curl -sI` sur l'URL sans cookie : 302, jamais 200.

Si une `SecurityPolicy` n'est pas `Accepted`, ne pas laisser la route exposée : retirer
`ai-gateway` de `gitops/apps/kustomization.yaml` le temps de corriger.

## Points à surveiller
- Les images de base vieillissent : le premier scan Trivy a bloqué 79 failles sur une base
  nginx 1.28 qui n'était plus reconstruite. Sans mise à jour automatique des digests
  (Renovate), le prochain build peut bloquer de la même façon.
- Le coût « en direct » ne valorise que les types connus (nœuds, disques Premium, IP, load
  balancer, ACR, plan de contrôle AKS, zones DNS). Un futur Azure Firewall devra y être ajouté.

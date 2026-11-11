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

1. App registration `azpl-ai-gateway` → nouveau client secret (90 jours au plus). Copier la
   colonne **Value** (40 caractères, affichée une seule fois), **pas Secret ID** : un
   identifiant déposé à la place du secret donne « OAuth flow failed » à la connexion et
   `AADSTS7000215` dans les journaux de connexion Entra (incident du 2026-11-10).
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
6. Supprimer l'ancien secret dans l'app registration.
7. Relecture immédiate et test du secret auprès d'Entra, sans afficher sa valeur
   (attendu : `longueur du secret : 40` et `"token_type":"Bearer"`) :
   ```bash
   az aks command invoke -g rg-azpl-aks-cluster-prd-frc-001 -n aks-azpl-prd-frc-001 \
     --subscription <subscription azpl-lz-aks> --command '
   kubectl annotate externalsecret oidc-client -n ai-gateway force-sync=$(date +%s) --overwrite
   sleep 15
   CID=$(kubectl get securitypolicy entra-oidc -n ai-gateway -o jsonpath="{.spec.oidc.clientID}")
   TID=$(kubectl get securitypolicy entra-oidc -n ai-gateway -o jsonpath="{.spec.oidc.provider.issuer}" | cut -d/ -f4)
   SEC=$(kubectl get secret oidc-client -n ai-gateway -o jsonpath="{.data.client-secret}" | base64 -d)
   echo "longueur du secret : ${#SEC}"
   curl -s -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" \
     --data-urlencode "client_id=$CID" --data-urlencode "client_secret=$SEC" \
     --data-urlencode "scope=https://graph.microsoft.com/.default" --data-urlencode grant_type=client_credentials \
     | grep -o "\"error_codes\":\[[0-9]*\]\|\"token_type\":\"Bearer\""'
   ```
   Envoy relit le Secret Kubernetes sans redémarrage.

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

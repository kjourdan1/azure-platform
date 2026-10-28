# AKS

## Problème résolu
Un cluster Kubernetes qui se reconstruit seul depuis Git : à chaque `lab-up`, Flux
réinstalle la plateforme et les applications décrites dans `gitops/`, sans credential stocké
et sans étape manuelle, puis `lab-down` détruit tout le soir pour tenir le budget.

## Approche retenue
Cluster dans son propre resource group (subscription `azpl-lz-aks`), raccordé au subnet,
au registre et au coffre de la couche `lz-aks`, qui restent permanents.

## Décisions et alternatives écartées
- **Identités sans secret** : OIDC + Workload Identity pour les pods, Entra ID + Azure RBAC
  pour les humains, comptes locaux désactivés, AcrPull sur l'identité kubelet.
- **Azure CNI Overlay + Cilium** : les pods ne consomment pas d'IP du VNet ; politiques
  réseau eBPF sans composant à installer.
- **Add-on Azure Policy** : les policies AKS de la landing zone s'appliquent dans le cluster.
- **Tier Free, un nœud B4s_v2** (4 vCPU, 16 Go) : environ 0,20 à 0,25 € par heure avec le load
  balancer. Un B2s (4 Go) ne tient pas Flux, les contrôleurs, Prometheus et l'application ;
  un seul B4s_v2 plutôt que deux B2s, pour moins de surcoût système par nœud. Le B4ms
  (B-series v1), premier choix, est refusé à la création : AKS ne propose que les B-series v2
  dans cette subscription en France Central (le message d'erreur liste les tailles permises).
- **KEDA en add-on AKS** : scaling sur événements (file RabbitMQ), géré par Microsoft.
- **Flux en extension AKS** (`gitops.tf`) plutôt que `flux bootstrap` : le bootstrap exige un
  jeton GitHub en écriture stocké ; ici le dépôt public est lu sans credential. Argo CD
  écarté : hors intégration native AKS, UI à sécuriser en plus.
- **Trois Kustomizations ordonnées** : `infra-controllers` → `infra-configs` → `apps`, avec
  `wait` : les CRD existent avant les ressources qui les utilisent.
- **Valeurs d'environnement par post-build substitution** : tenant, subscription, zone DNS,
  coffre et client IDs arrivent dans `gitops/` sous forme de `${VAR}`, jamais committés.
  Marquées sensibles : le plan publié n'affiche pas le contenu des Kustomizations.
- **Credentials fédérés ici, identités dans `lz-aks`** : l'URL de l'émetteur OIDC change à
  chaque création de cluster ; l'identité et son rôle, eux, sont stables.
- **Pas de Container Insights** : ingestion payante ; observabilité par kube-prometheus-stack.
- **Cluster public** : un cluster privé exige un runner dans le VNet (cible self-hosted).

- **Cycle de vie lab** : `lab-up` (manuel, approbation `prd`) applique cette couche ;
  `lab-down` (chaque soir à 22 h UTC) supprime le cluster avec une identité qui ne sait faire
  que ça. Un merge n'applique jamais cette couche, pour ne pas relancer la facture.
- **`az aks delete` plutôt que `terraform destroy`** : le destroy exigerait l'identité apply
  et donc une approbation chaque soir. Le state se réaligne au plan suivant.

## Limites connues
- Pas de SLA (tier Free), pool unique système et applications.
- Les exceptions checkov sont justifiées dans `cluster.tf`.

- L'attribution AcrPull de l'ancienne identité kubelet reste orpheline jusqu'au `lab-up`
  suivant, qui la remplace.
- GitHub désactive les workflows planifiés après 60 jours sans activité sur le dépôt.

## Installation
PR → plan commenté → merge → `lab-up` avec approbation. `lab-down` tourne seul chaque soir.
Accès : `az aks get-credentials -g <rg> -n <cluster>` puis `kubelogin convert-kubeconfig -l azurecli`.
Convergence après `lab-up` : `kubectl get kustomizations -n flux-system` (trois `Ready=True`) ;
`kubectl get cm cluster-info -n flux-system -o jsonpath='{.data.dnsZone}'` prouve que la
substitution fonctionne.

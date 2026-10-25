# AKS

## Problème résolu
Un cluster Kubernetes de production prêt pour le GitOps et pour le chemin des secrets
sans credential stocké, créable et destructible à la demande pour tenir le budget.

## Approche retenue
Cluster dans son propre resource group (subscription `azpl-lz-aks`), raccordé au subnet,
au registre et au coffre de la couche `lz-aks`, qui restent permanents.

## Décisions et alternatives écartées
- **Identités sans secret** : OIDC + Workload Identity pour les pods, Entra ID + Azure RBAC
  pour les humains, comptes locaux désactivés, AcrPull sur l'identité kubelet.
- **Azure CNI Overlay + Cilium** : les pods ne consomment pas d'IP du VNet ; politiques
  réseau eBPF sans composant à installer.
- **Add-on Azure Policy** : les policies AKS de la landing zone s'appliquent dans le cluster.
- **Tier Free, un nœud B2s** : environ 2 € par jour de fonctionnement avec le load balancer.
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

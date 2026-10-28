#!/bin/bash
# Flux remplace par une chaîne vide toute variable ${VAR} absente de la post-build
# substitution, sans erreur. Ce contrôle échoue si gitops/ utilise une variable que
# infra/aks ne fournit pas (clés de local.flux_substitutions).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
locals_file="$root/infra/aks/locals.tf"

provided=$(awk '/flux_substitutions *= *sensitive\(\{/{f=1;next} f&&/^ *\}\)/{f=0} f' "$locals_file" |
  sed -nE 's/^ *([A-Z][A-Z0-9_]*) *=.*/\1/p' | sort -u)

used=$(grep -rhoE '\$\{[A-Za-z_][A-Za-z0-9_]*' "$root/gitops" --include='*.yaml' --include='*.yml' |
  sed 's/^\${//' | sort -u || true)

unknown=$(comm -23 <(printf '%s\n' "$used" | sed '/^$/d') <(printf '%s\n' "$provided"))

if [ -n "$unknown" ]; then
  echo "Variables utilisées dans gitops/ mais absentes de flux_substitutions (infra/aks/locals.tf) :" >&2
  printf '%s\n' "$unknown" | sed 's/^/  /' >&2
  exit 1
fi
echo "Substitutions OK : $(printf '%s\n' "$used" | sed '/^$/d' | wc -l) variable(s) utilisée(s), toutes fournies."

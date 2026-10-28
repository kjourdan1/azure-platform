#!/usr/bin/env python3
"""Valide ce que Flux appliquera, sans cluster ni accès Azure.

Pour chaque niveau de gitops/ : kustomize build, substitution des ${VAR} par des valeurs
d'exemple (comme le fait Flux avec les vraies), validation kubeconform contre les schémas
Kubernetes et ceux des CRD. Puis chaque HelmRelease est rendue avec helm template et chaque
conteneur doit déclarer allowPrivilegeEscalation: false sans privileged : c'est la règle
que Gatekeeper (policies ALZ Deny-Priv-Esc-AKS / Deny-Privileged-AKS) appliquera au cluster.

Outils attendus dans le PATH : kustomize, kubeconform, helm.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
LEVELS = ["gitops/infrastructure/controllers", "gitops/infrastructure/configs", "gitops/apps"]
CRD_SCHEMAS = "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

# Valeurs d'exemple, au format des vraies : un format invalide échouerait ici comme en vrai.
SAMPLES = {
    "AZURE_TENANT_ID": "00000000-0000-0000-0000-000000000001",
    "AZURE_SUBSCRIPTION_ID": "00000000-0000-0000-0000-000000000002",
    "DNS_ZONE": "lab.example.com",
    "DNS_RESOURCE_GROUP": "rg-example",
    "KEY_VAULT_URL": "https://kv-example.vault.azure.net/",
    "ESO_CLIENT_ID": "00000000-0000-0000-0000-000000000003",
    "EXTERNAL_DNS_CLIENT_ID": "00000000-0000-0000-0000-000000000004",
    "SECRET_EXPIRES_AT": "2030-01-01T00:00:00Z",
}


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw).stdout


def substitute(text):
    def repl(m):
        name = m.group(1)
        if name not in SAMPLES:
            sys.exit(f"variable ${{{name}}} sans valeur d'exemple dans scripts/validate-gitops.py")
        return SAMPLES[name]
    return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", repl, text)


def check_containers(docs, origin):
    bad = []
    for doc in docs:
        if not isinstance(doc, dict):
            continue
        spec = doc.get("spec") or {}
        template = spec.get("template") or spec.get("jobTemplate", {}).get("spec", {}).get("template") or {}
        pod = template.get("spec") or (spec if doc.get("kind") == "Pod" else {})
        # Les pods de test Helm ne sont jamais lancés par Flux (tests désactivés par défaut).
        if "helm.sh/hook" in (doc.get("metadata", {}).get("annotations") or {}):
            continue
        for kind in ("initContainers", "containers"):
            for c in pod.get(kind) or []:
                sc = c.get("securityContext") or {}
                if sc.get("allowPrivilegeEscalation") is not False or sc.get("privileged"):
                    bad.append(f"{origin}: {doc['kind']}/{doc['metadata']['name']} {c['name']}")
    return bad


def main():
    failures = []
    releases, repositories = [], {}
    for level in LEVELS:
        built = substitute(run(["kustomize", "build", str(ROOT / level)]))
        proc = subprocess.run(
            ["kubeconform", "-strict", "-summary", "-schema-location", "default",
             "-schema-location", CRD_SCHEMAS],
            input=built, text=True, capture_output=True)
        print(f"== {level}\n{proc.stdout.strip()}")
        if proc.returncode:
            failures.append(f"kubeconform: {level}")
        for doc in yaml.safe_load_all(built):
            if not doc:
                continue
            if doc["kind"] == "HelmRepository":
                repositories[(doc["metadata"]["namespace"], doc["metadata"]["name"])] = doc["spec"]
            elif doc["kind"] == "HelmRelease":
                releases.append(doc)
        failures += [f"container: {b}" for b in check_containers(yaml.safe_load_all(built), level)]

    for rel in releases:
        ns, name = rel["metadata"]["namespace"], rel["metadata"]["name"]
        chart = rel["spec"]["chart"]["spec"]
        ref = chart["sourceRef"]
        repo = repositories[(ref.get("namespace", ns), ref["name"])]
        if repo.get("type") == "oci":
            source = [f"{repo['url']}/{chart['chart']}"]
        else:
            source = [chart["chart"], "--repo", repo["url"]]
        with tempfile.NamedTemporaryFile("w", suffix=".yaml") as values:
            yaml.safe_dump(rel["spec"].get("values") or {}, values)
            values.flush()
            rendered = run(["helm", "template", name, *source, "--version", chart["version"],
                            "-n", ns, "-f", values.name])
        bad = check_containers(yaml.safe_load_all(rendered), f"{ns}/{name}")
        print(f"== HelmRelease {ns}/{name} ({chart['chart']} {chart['version']}): "
              f"{'OK' if not bad else f'{len(bad)} conteneur(s) non conforme(s)'}")
        failures += [f"container: {b}" for b in bad]

    if failures:
        print("\nÉchecs :", *failures, sep="\n  ")
        return 1
    print("\nTout est valide.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

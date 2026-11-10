"""Coût en direct : ce qui tourne maintenant, valorisé au tarif public de l'heure.

Resource Graph donne l'état courant (nœuds, disques, IP, load balancers...) sans attendre la
facturation. Les services facturés à l'usage (tokens, logs, opérations Key Vault, stockage)
n'ont pas de tarif horaire : ils sont listés comme tels, pas estimés.
"""

from .arm import ArmClient
from .prices import RetailPrices

QUERY = """
resources
| where type in~ ('microsoft.compute/virtualmachinescalesets', 'microsoft.compute/disks',
    'microsoft.network/publicipaddresses', 'microsoft.network/loadbalancers',
    'microsoft.containerregistry/registries', 'microsoft.containerservice/managedclusters',
    'microsoft.network/dnszones')
| join kind=leftouter (resourcecontainers
    | where type =~ 'microsoft.resources/subscriptions'
    | project subscriptionId, subscription = name) on subscriptionId
| project name, type = tolower(type), location, resourceGroup, subscription,
    skuName = tostring(sku.name), skuTier = tostring(sku.tier), capacity = toint(sku.capacity),
    osDiskType = tostring(properties.virtualMachineProfile.storageProfile.osDisk.managedDisk.storageAccountType),
    osDiskSize = toint(properties.virtualMachineProfile.storageProfile.osDisk.diskSizeGB),
    diskSize = toint(properties.diskSizeGB),
    lbRules = array_length(properties.loadBalancingRules) + array_length(properties.outboundRules)
| order by subscription asc, type asc, name asc
"""

USAGE_BASED = [
    "Tokens Foundry (comptés en direct par le chat)",
    "Log Analytics (ingestion)",
    "Opérations Key Vault",
    "Stockage et bande passante",
]


async def _price(item: dict, prices: RetailPrices) -> tuple[str, str, float | None]:
    """(catégorie, détail, €/h) d'une ressource."""
    kind, region, sku = item["type"], item["location"], item.get("skuName") or ""
    if kind.endswith("virtualmachinescalesets"):
        count = item.get("capacity") or 0
        vm = await prices.vm(sku, region)
        disk = 0.0
        if item.get("osDiskType") == "Premium_LRS" and item.get("osDiskSize"):
            disk = await prices.premium_disk(item["osDiskSize"], region) or 0.0
        label = "Nœuds AKS" if item["resourceGroup"].lower().startswith("mc_") else "Machines virtuelles"
        hourly = None if vm is None else count * (vm + disk)
        return label, f"{count} × {sku}", hourly
    if kind.endswith("/disks"):
        if sku != "Premium_LRS" or not item.get("diskSize"):
            return "Disques", sku or "inconnu", None
        return "Disques", f"{sku} {item['diskSize']} Go", await prices.premium_disk(item["diskSize"], region)
    if kind.endswith("publicipaddresses"):
        return "IP publiques", sku, await prices.public_ip(region) if sku == "Standard" else None
    if kind.endswith("loadbalancers"):
        if not item.get("lbRules"):
            return "Load balancers", f"{sku}, sans règle", 0.0
        return "Load balancers", sku, await prices.load_balancer() if sku == "Standard" else None
    if kind.endswith("registries"):
        return "Registre d'images", sku, await prices.container_registry(sku, region)
    if kind.endswith("managedclusters"):
        tier = item.get("skuTier") or "Free"
        return "Plan de contrôle AKS", tier, await prices.aks_control_plane(tier, region)
    if kind.endswith("dnszones"):
        return "Zones DNS", "zone publique", await prices.dns_zone()
    return "Autre", kind, None


async def live(arm: ArmClient, prices: RetailPrices) -> dict:
    result = await arm.request(
        "POST", "/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01",
        json={"query": QUERY, "options": {"resultFormat": "objectArray", "$top": 1000}},
    )
    items = []
    for resource in result.get("data", []):
        category, detail, hourly = await _price(resource, prices)
        items.append({
            "name": resource["name"],
            "category": category,
            "detail": detail,
            "subscription": resource.get("subscription"),
            "resource_group": resource["resourceGroup"],
            "hourly": None if hourly is None else round(hourly, 5),
        })
    hourly_total = sum(i["hourly"] or 0 for i in items)
    return {
        "currency": prices.currency,
        "hourly": round(hourly_total, 4),
        "daily": round(hourly_total * 24, 3),
        "monthly": round(hourly_total * 730, 2),
        "cluster_running": any(i["category"] == "Nœuds AKS" and (i["hourly"] or 0) > 0 for i in items),
        "items": items,
        "usage_based": USAGE_BASED,
    }

"""Tarifs publics Azure (API Retail Prices, sans authentification), ramenés à l'heure.

Les noms de compteurs sont ceux de la facture réelle (Cost Management, dimension Meter),
vérifiés un à un : un compteur introuvable donne None, jamais un prix inventé.
"""

import time

import httpx

RETAIL = "https://prices.azure.com/api/retail/prices"
HOURS_PER_MONTH = 730
TTL_SECONDS = 24 * 3600

# Taille du disque (Go) -> palier Premium SSD facturé.
PREMIUM_TIERS = [(4, "P1"), (8, "P2"), (16, "P3"), (32, "P4"), (64, "P6"), (128, "P10"),
                 (256, "P15"), (512, "P20"), (1024, "P30"), (2048, "P40")]


def per_hour(price: float, unit: str) -> float | None:
    unit = unit.lower().replace(" ", "")
    if unit in ("1hour", "1/hour"):
        return price
    if unit in ("1/day", "1day"):
        return price / 24
    if unit in ("1/month", "1month"):
        return price / HOURS_PER_MONTH
    return None


def premium_tier(size_gb: int) -> str | None:
    return next((tier for limit, tier in PREMIUM_TIERS if size_gb <= limit), None)


class RetailPrices:
    def __init__(self, http: httpx.AsyncClient, currency: str = "EUR"):
        self._http = http
        self.currency = currency
        self._cache: dict[str, tuple[float, dict | None]] = {}

    async def _first(self, odata_filter: str, accept=lambda item: True) -> dict | None:
        cached = self._cache.get(odata_filter)
        if cached and time.monotonic() - cached[0] < TTL_SECONDS:
            return cached[1]
        params = {"currencyCode": self.currency, "$filter": odata_filter}
        response = await self._http.get(RETAIL, params=params)
        response.raise_for_status()
        items = [i for i in response.json().get("Items", [])
                 if i.get("type") == "Consumption" and i.get("retailPrice", 0) > 0 and accept(i)]
        # Plusieurs paliers possibles : on garde le premier (tierMinimumUnits le plus bas).
        item = min(items, key=lambda i: i.get("tierMinimumUnits", 0)) if items else None
        self._cache[odata_filter] = (time.monotonic(), item)
        return item

    async def _hourly(self, odata_filter: str, accept=lambda item: True) -> float | None:
        item = await self._first(odata_filter, accept)
        return per_hour(item["retailPrice"], item["unitOfMeasure"]) if item else None

    async def vm(self, sku: str, region: str) -> float | None:
        return await self._hourly(
            f"serviceName eq 'Virtual Machines' and armRegionName eq '{region}' "
            f"and armSkuName eq '{sku}' and priceType eq 'Consumption'",
            lambda i: "Windows" not in i["productName"]
            and not any(w in i["meterName"] for w in ("Spot", "Low Priority")),
        )

    async def premium_disk(self, size_gb: int, region: str) -> float | None:
        tier = premium_tier(size_gb)
        if tier is None:
            return None
        return await self._hourly(
            f"armRegionName eq '{region}' and meterName eq '{tier} LRS Disk'",
            lambda i: i["productName"] == "Premium SSD Managed Disks",
        )

    async def public_ip(self, region: str) -> float | None:
        return await self._hourly(
            f"armRegionName eq '{region}' and meterName eq 'Standard IPv4 Static Public IP'")

    async def load_balancer(self) -> float | None:
        # Tarif unique, publié sous la région « Global » : 5 premières règles incluses.
        return await self._hourly(
            "serviceName eq 'Load Balancer' and armRegionName eq 'Global' "
            "and meterName eq 'Standard Included LB Rules and Outbound Rules'")

    async def container_registry(self, sku: str, region: str) -> float | None:
        return await self._hourly(
            f"serviceName eq 'Container Registry' and armRegionName eq '{region}' "
            f"and meterName eq '{sku} Registry Unit'")

    async def dns_zone(self) -> float | None:
        # Palier des 25 premières zones (le plus cher) ; l'unité publiée est « 1 » par mois.
        item = await self._first(
            "serviceName eq 'Azure DNS' and armRegionName eq 'Zone 1' and meterName eq 'Public Zone'")
        return item["retailPrice"] / HOURS_PER_MONTH if item else None

    async def aks_control_plane(self, tier: str, region: str) -> float | None:
        if tier.lower() == "free":
            return 0.0
        return await self._hourly(
            f"serviceName eq 'Azure Kubernetes Service' and armRegionName eq '{region}' "
            "and meterName eq 'Standard Uptime SLA'")

    async def model_tokens(self, meter_prefix: str, region: str) -> dict[str, float | None]:
        """Prix au million de tokens d'un modèle Foundry (déploiement Data Zone)."""
        result = {}
        for key, part in (("input", "Inp"), ("output", "Opt"), ("cached_input", "cd Inp")):
            item = await self._first(
                f"serviceName eq 'Foundry Models' and armRegionName eq '{region}' "
                f"and meterName eq '{meter_prefix} {part} Dz 1M Tokens'")
            result[key] = item["retailPrice"] if item else None
        return result

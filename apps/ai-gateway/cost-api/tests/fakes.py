class FakeArm:
    """ArmClient de test : réponses par préfixe de chemin, appels enregistrés."""

    def __init__(self, routes: dict):
        self.routes = routes
        self.calls: list[tuple[str, str, dict | None]] = []

    async def request(self, method, path, **kwargs):
        self.calls.append((method, path, kwargs.get("json")))
        for prefix, response in self.routes.items():
            if path.startswith(prefix):
                return response(path, kwargs.get("json")) if callable(response) else response
        raise AssertionError(f"unexpected call {method} {path}")

    async def close(self):
        pass


class FakePrices:
    currency = "EUR"

    async def vm(self, sku, region):
        return {"Standard_D4as_v7": 0.1912}.get(sku)

    async def premium_disk(self, size_gb, region):
        return 5.7345 / 730 if size_gb <= 32 else None

    async def public_ip(self, region):
        return 0.0045

    async def load_balancer(self):
        return 0.0224

    async def container_registry(self, sku, region):
        return 0.1496 / 24

    async def dns_zone(self):
        return 0.4489 / 730

    async def aks_control_plane(self, tier, region):
        return 0.0 if tier == "Free" else 0.0898

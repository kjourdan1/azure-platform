"""Client Azure Resource Manager minimal : jeton Entra (Workload Identity), retry sur 429."""

import asyncio
import logging

import httpx
from azure.identity.aio import DefaultAzureCredential

ARM = "https://management.azure.com"
SCOPE = "https://management.azure.com/.default"
MAX_RETRY_DELAY = 60.0
log = logging.getLogger(__name__)


def retry_delay(headers: httpx.Headers) -> float:
    """Délai demandé par Azure. Cost Management l'annonce dans ses propres en-têtes
    (x-ms-ratelimit-microsoft.costmanagement-*-retry-after), pas toujours dans Retry-After :
    on prend le plus long, plafonné."""
    delays = []
    for name, value in headers.items():
        if name.lower() == "retry-after" or name.lower().endswith("-retry-after"):
            try:
                delays.append(float(value))
            except ValueError:
                continue
    return min(max(delays, default=5.0), MAX_RETRY_DELAY)


class ArmClient:
    def __init__(self, http: httpx.AsyncClient, credential=None):
        self._http = http
        # Sur AKS, le webhook Workload Identity injecte AZURE_CLIENT_ID, AZURE_TENANT_ID et
        # AZURE_FEDERATED_TOKEN_FILE : DefaultAzureCredential choisit WorkloadIdentityCredential.
        self._credential = credential or DefaultAzureCredential()

    async def _headers(self) -> dict:
        token = await self._credential.get_token(SCOPE)
        return {"Authorization": f"Bearer {token.token}"}

    async def request(self, method: str, path: str, **kwargs) -> dict:
        """Appel ARM. Cost Management limite fortement le débit : un 429 est réessayé une
        fois après le délai demandé (plafonné), puis remonté à l'appelant, qui sert son cache
        ou réessaie plus tard (préchargement au démarrage)."""
        url = path if path.startswith("https://") else f"{ARM}{path}"
        for attempt in range(2):
            response = await self._http.request(method, url, headers=await self._headers(), **kwargs)
            if response.status_code == 429 and attempt == 0:
                delay = retry_delay(response.headers)
                log.warning("ARM 429 on %s, retry in %.0fs", path.split("?")[0], delay)
                await asyncio.sleep(delay)
                continue
            response.raise_for_status()
            return response.json()
        raise RuntimeError("unreachable")

    async def close(self) -> None:
        await self._credential.close()

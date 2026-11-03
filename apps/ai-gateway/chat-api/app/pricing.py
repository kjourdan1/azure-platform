"""Coût d'un échange, à partir des prix publiés par cost-api (appel interne au cluster)."""

import logging
import time

import httpx

log = logging.getLogger(__name__)
TTL_SECONDS = 3600


class ModelPricing:
    def __init__(self, http: httpx.AsyncClient, cost_api_url: str):
        self._http = http
        self._url = f"{cost_api_url.rstrip('/')}/api/cost/model-prices"
        self._prices: dict | None = None
        self._fetched_at = 0.0

    async def prices(self) -> dict | None:
        if self._prices and time.monotonic() - self._fetched_at < TTL_SECONDS:
            return self._prices
        try:
            response = await self._http.get(self._url, timeout=5.0)
            response.raise_for_status()
            body = response.json()
            self._prices = {"currency": body["currency"], **body["per_million"]}
            self._fetched_at = time.monotonic()
        except (httpx.HTTPError, KeyError, ValueError) as error:
            # Le chat reste utilisable sans cost-api : seul le coût manque.
            log.warning("model prices unavailable: %s", error)
        return self._prices


def exchange_cost(usage: dict, prices: dict | None) -> float | None:
    """Les tokens servis depuis le cache sont facturés au tarif « cached input »."""
    if not prices or None in (prices.get("input"), prices.get("output")):
        return None
    cached = usage.get("cached_input", 0)
    fresh = usage.get("input", 0) - cached
    cached_price = prices.get("cached_input") or prices["input"]
    total = fresh * prices["input"] + cached * cached_price + usage.get("output", 0) * prices["output"]
    return total / 1_000_000

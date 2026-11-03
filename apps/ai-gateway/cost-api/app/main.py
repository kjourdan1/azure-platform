"""cost-api : coût facturé et coût en direct de toute la plateforme, en lecture seule."""

import logging
import os
from contextlib import asynccontextmanager
from datetime import UTC, date, datetime

import httpx
from fastapi import FastAPI, HTTPException

from . import billing, inventory
from .arm import ArmClient
from .cache import StaleCache
from .prices import RetailPrices

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")

# Cost Management : quelques appels par minute et par locataire ; la donnée change au mieux
# toutes les quelques heures. Resource Graph et l'état des ressources bougent à la minute.
BILLED_TTL = float(os.getenv("BILLED_REFRESH_SECONDS", "900"))
LIVE_TTL = float(os.getenv("LIVE_REFRESH_SECONDS", "60"))
MODEL_METER = os.getenv("MODEL_METER", "5.4 mini")
MODEL_REGION = os.getenv("MODEL_REGION", "francecentral")


@asynccontextmanager
async def lifespan(app: FastAPI):
    http = httpx.AsyncClient(timeout=httpx.Timeout(30.0))
    app.state.arm = ArmClient(http)
    app.state.prices = RetailPrices(http)
    app.state.billed = StaleCache(BILLED_TTL)
    app.state.live = StaleCache(LIVE_TTL)
    app.state.model = StaleCache(24 * 3600)
    yield
    await app.state.arm.close()
    await http.aclose()


app = FastAPI(title="cost-api", lifespan=lifespan, docs_url=None, redoc_url=None)


def _envelope(payload: dict, stale: bool, cache: StaleCache) -> dict:
    return {**payload, "stale": stale, "refreshed_at": datetime.now(UTC).isoformat(timespec="seconds"),
            "refresh_seconds": int(cache.ttl)}


async def _cached(cache: StaleCache, load) -> dict:
    try:
        value, stale = await cache.get(load)
    except Exception as error:  # premier chargement impossible : rien à servir
        raise HTTPException(status_code=503, detail=f"source indisponible ({type(error).__name__})") from error
    return _envelope(value, stale, cache)


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok"}


@app.get("/api/cost/billed")
async def billed() -> dict:
    state = app.state
    return await _cached(state.billed, lambda: billing.billed(state.arm, date.today()))


@app.get("/api/cost/live")
async def live() -> dict:
    state = app.state
    return await _cached(state.live, lambda: inventory.live(state.arm, state.prices))


@app.get("/api/cost/model-prices")
async def model_prices() -> dict:
    """Prix au million de tokens du modèle déployé, lus par chat-api (appel interne)."""
    state = app.state

    async def load() -> dict:
        per_million = await state.prices.model_tokens(MODEL_METER, MODEL_REGION)
        return {"currency": state.prices.currency, "meter": MODEL_METER, "per_million": per_million}

    return await _cached(state.model, load)

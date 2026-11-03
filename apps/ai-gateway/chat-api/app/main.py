"""chat-api : conversation avec le modèle Foundry, en streaming, tokens et coût comptés."""

import asyncio
import json
import logging
import os
from contextlib import asynccontextmanager
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field, field_validator

from .foundry import Foundry, UpstreamError
from .pricing import ModelPricing, exchange_cost

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
log = logging.getLogger("chat-api")

MAX_TOKENS = int(os.getenv("MAX_COMPLETION_TOKENS", "800"))
MAX_MESSAGE_CHARS = int(os.getenv("MAX_MESSAGE_CHARS", "4000"))
MAX_HISTORY = int(os.getenv("MAX_HISTORY", "12"))
MAX_CONCURRENT = int(os.getenv("MAX_CONCURRENT", "4"))
SYSTEM_PROMPT = os.getenv(
    "SYSTEM_PROMPT",
    "Tu es l'assistant de la plateforme Azure « azpl » : landing zone ALZ, AKS piloté par "
    "GitOps (Flux), Azure AI Foundry. Réponds en français, de façon concise et factuelle. "
    "Si tu ne sais pas, dis-le.",
)


class Message(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1)

    @field_validator("content")
    @classmethod
    def bounded(cls, value: str) -> str:
        if len(value) > MAX_MESSAGE_CHARS:
            raise ValueError(f"message de plus de {MAX_MESSAGE_CHARS} caractères")
        return value


class ChatRequest(BaseModel):
    messages: list[Message] = Field(min_length=1)

    @field_validator("messages")
    @classmethod
    def ends_with_user(cls, messages: list[Message]) -> list[Message]:
        if messages[-1].role != "user":
            raise ValueError("le dernier message doit venir de l'utilisateur")
        return messages[-MAX_HISTORY:]


class Totals:
    """Cumul depuis le démarrage du pod (une réplique : pas d'état partagé à gérer)."""

    def __init__(self):
        self.requests = 0
        self.input = 0
        self.output = 0
        self.cost = 0.0

    def add(self, usage: dict, cost: float | None) -> None:
        self.requests += 1
        self.input += usage.get("input", 0)
        self.output += usage.get("output", 0)
        self.cost += cost or 0.0


@asynccontextmanager
async def lifespan(app: FastAPI):
    http = httpx.AsyncClient(timeout=httpx.Timeout(60.0, connect=10.0))
    app.state.foundry = Foundry(http, os.environ["FOUNDRY_ENDPOINT"], os.environ["FOUNDRY_DEPLOYMENT"])
    app.state.pricing = ModelPricing(http, os.getenv("COST_API_URL", "http://cost-api"))
    app.state.slots = asyncio.Semaphore(MAX_CONCURRENT)
    app.state.totals = Totals()
    yield
    await app.state.foundry.close()
    await http.aclose()


app = FastAPI(title="chat-api", lifespan=lifespan, docs_url=None, redoc_url=None)


def _event(name: str, payload: dict) -> str:
    return f"event: {name}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok"}


@app.get("/api/chat/stats")
async def stats() -> dict:
    totals = app.state.totals
    prices = await app.state.pricing.prices()
    return {
        "deployment": app.state.foundry.deployment,
        "requests": totals.requests,
        "input_tokens": totals.input,
        "output_tokens": totals.output,
        "cost": round(totals.cost, 6),
        "currency": (prices or {}).get("currency", "EUR"),
        "prices_per_million": prices,
    }


@app.post("/api/chat")
async def chat(request: ChatRequest) -> StreamingResponse:
    slots: asyncio.Semaphore = app.state.slots
    if slots.locked():
        raise HTTPException(status_code=429, detail="trop de conversations en cours, réessayez")
    await slots.acquire()

    messages = [{"role": "system", "content": SYSTEM_PROMPT}] + [m.model_dump() for m in request.messages]

    async def events():
        state = app.state
        estimate = 0
        try:
            yield _event("meta", {"deployment": state.foundry.deployment})
            async for item in state.foundry.stream(messages, MAX_TOKENS):
                if item["type"] == "delta":
                    # Un fragment de texte vaut à peu près un token : compteur en direct,
                    # remplacé par la valeur exacte quand Foundry envoie la consommation.
                    estimate += 1
                    yield _event("delta", {"text": item["text"], "output_estimate": estimate})
                else:
                    prices = await state.pricing.prices()
                    cost = exchange_cost(item, prices)
                    state.totals.add(item, cost)
                    yield _event("usage", {
                        **item, "cost": cost, "currency": (prices or {}).get("currency", "EUR")})
            yield _event("done", {})
        except UpstreamError as error:
            log.warning("foundry error %s", error)
            yield _event("error", {"message": f"Foundry a répondu {error.status}", "detail": error.message})
        except httpx.HTTPError as error:
            log.warning("foundry unreachable: %s", error)
            yield _event("error", {"message": "Foundry injoignable"})
        finally:
            slots.release()

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        # Pas de mise en tampon par la Gateway : chaque fragment part tout de suite.
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )

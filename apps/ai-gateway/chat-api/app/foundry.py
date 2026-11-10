"""Appel en streaming du déploiement Foundry (API v1 compatible OpenAI), sans clé."""

import json
from collections.abc import AsyncIterator

import httpx
from azure.identity.aio import DefaultAzureCredential

SCOPE = "https://cognitiveservices.azure.com/.default"


class Foundry:
    def __init__(self, http: httpx.AsyncClient, endpoint: str, deployment: str, credential=None):
        self._http = http
        self._url = f"{endpoint.rstrip('/')}/openai/v1/chat/completions"
        self.deployment = deployment
        # Workload Identity sur AKS : l'identité ai-chat n'a que l'inférence sur ce compte.
        self._credential = credential or DefaultAzureCredential()

    async def stream(self, messages: list[dict], max_tokens: int) -> AsyncIterator[dict]:
        """Événements normalisés : {"type": "delta", "text"} puis {"type": "usage", ...}."""
        token = await self._credential.get_token(SCOPE)
        body = {
            "model": self.deployment,
            "messages": messages,
            "max_completion_tokens": max_tokens,
            "stream": True,
            # Dernier fragment : consommation exacte (prompt, cache, complétion).
            "stream_options": {"include_usage": True},
        }
        headers = {"Authorization": f"Bearer {token.token}"}
        async with self._http.stream("POST", self._url, json=body, headers=headers) as response:
            if response.status_code >= 400:
                await response.aread()
                raise UpstreamError(response.status_code, _error_message(response))
            async for line in response.aiter_lines():
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                chunk = json.loads(data)
                for choice in chunk.get("choices") or []:
                    text = (choice.get("delta") or {}).get("content")
                    if text:
                        yield {"type": "delta", "text": text}
                usage = chunk.get("usage")
                if usage:
                    details = usage.get("prompt_tokens_details") or {}
                    yield {
                        "type": "usage",
                        "model": chunk.get("model"),
                        "input": usage.get("prompt_tokens", 0),
                        "cached_input": details.get("cached_tokens", 0),
                        "output": usage.get("completion_tokens", 0),
                    }

    async def close(self) -> None:
        await self._credential.close()


class UpstreamError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(f"{status}: {message}")
        self.status = status
        self.message = message


def _error_message(response: httpx.Response) -> str:
    try:
        return response.json().get("error", {}).get("message", "")[:200]
    except ValueError:
        return response.text[:200]

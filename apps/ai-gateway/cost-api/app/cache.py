"""Cache à durée de vie qui sert la dernière valeur connue si le rafraîchissement échoue."""

import asyncio
import logging
import time
from collections.abc import Awaitable, Callable
from typing import Any

log = logging.getLogger(__name__)


class StaleCache:
    def __init__(self, ttl_seconds: float, clock: Callable[[], float] = time.monotonic):
        self.ttl = ttl_seconds
        self._clock = clock
        self._value: Any = None
        self._fetched_at: float | None = None
        self._lock = asyncio.Lock()
        self.last_error: str | None = None

    @property
    def empty(self) -> bool:
        return self._fetched_at is None

    @property
    def loading(self) -> bool:
        return self._lock.locked()

    async def get(self, load: Callable[[], Awaitable[Any]]) -> tuple[Any, bool]:
        """Renvoie (valeur, périmée). Un seul rafraîchissement à la fois, quel que soit le
        nombre de navigateurs ouverts : c'est ce qui protège les quotas d'API d'Azure."""
        async with self._lock:
            fresh = self._fetched_at is not None and self._clock() - self._fetched_at < self.ttl
            if fresh:
                return self._value, False
            try:
                self._value = await load()
                self._fetched_at = self._clock()
                self.last_error = None
                return self._value, False
            except Exception as error:  # noqa: BLE001 - toute panne amont sert le cache
                self.last_error = type(error).__name__
                log.warning("refresh failed: %s", error)
                if self._fetched_at is None:
                    raise
                return self._value, True

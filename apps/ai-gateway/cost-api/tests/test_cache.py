import asyncio

import pytest

from app.cache import StaleCache


def test_fresh_value_is_not_reloaded_and_stale_value_is_served_on_error():
    now = [0.0]
    cache = StaleCache(60, clock=lambda: now[0])
    calls = []

    async def ok():
        calls.append("ok")
        return {"v": len(calls)}

    async def boom():
        raise RuntimeError("429")

    async def run():
        first = await cache.get(ok)
        second = await cache.get(ok)
        now[0] = 61
        third = await cache.get(boom)
        return first, second, third

    first, second, third = asyncio.run(run())
    assert first == ({"v": 1}, False)
    assert second == ({"v": 1}, False)
    assert third == ({"v": 1}, True)
    assert cache.last_error == "RuntimeError"


def test_first_load_failure_propagates():
    cache = StaleCache(60)

    async def boom():
        raise RuntimeError("down")

    with pytest.raises(RuntimeError):
        asyncio.run(cache.get(boom))

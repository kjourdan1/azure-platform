import asyncio

import httpx

from app import main
from app.arm import retry_delay
from app.cache import StaleCache


def test_retry_delay_reads_cost_management_headers():
    headers = httpx.Headers({
        "Retry-After": "5",
        "x-ms-ratelimit-microsoft.costmanagement-qpu-retry-after": "42",
    })
    assert retry_delay(headers) == 42
    assert retry_delay(httpx.Headers({"x-ms-ratelimit-microsoft.costmanagement-entity-retry-after": "900"})) == 60
    assert retry_delay(httpx.Headers({})) == 5
    assert retry_delay(httpx.Headers({"Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"})) == 5


def test_warmup_retries_until_cost_management_answers():
    calls, slept = [], []

    async def load():
        calls.append(1)
        if len(calls) < 3:
            raise httpx.HTTPStatusError("429", request=None, response=None)
        return {"month_to_date": 1.0}

    async def fake_sleep(seconds):
        slept.append(seconds)

    cache = StaleCache(900)
    ok = asyncio.run(main.warm_billed(load, cache, delays=[15, 30, 60], sleep=fake_sleep))
    assert ok is True
    assert len(calls) == 3
    assert slept == [15, 30]
    assert not cache.empty


def test_warmup_gives_up_after_its_delays():
    async def load():
        raise RuntimeError("down")

    async def fake_sleep(seconds):
        pass

    cache = StaleCache(900)
    assert asyncio.run(main.warm_billed(load, cache, delays=[1, 1], sleep=fake_sleep)) is False
    assert cache.empty

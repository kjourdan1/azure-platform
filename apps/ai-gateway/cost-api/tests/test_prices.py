import asyncio

import httpx
import pytest
import respx

from app.prices import RETAIL, RetailPrices, per_hour, premium_tier


def test_per_hour_units():
    assert per_hour(0.19, "1 Hour") == 0.19
    assert per_hour(2.4, "1/Day") == pytest.approx(0.1)
    assert per_hour(7.3, "1/Month") == pytest.approx(0.01)
    assert per_hour(1.0, "10K") is None


def test_premium_tier_by_size():
    assert premium_tier(30) == "P4"
    assert premium_tier(32) == "P4"
    assert premium_tier(33) == "P6"
    assert premium_tier(5000) is None


@respx.mock
def test_vm_price_skips_windows_and_spot():
    items = [
        {"type": "Consumption", "retailPrice": 0.3564, "productName": "Dasv7 Series Windows",
         "meterName": "D4as v7", "unitOfMeasure": "1 Hour"},
        {"type": "Consumption", "retailPrice": 0.0353, "productName": "Dasv7 Series",
         "meterName": "D4as v7 Spot", "unitOfMeasure": "1 Hour"},
        {"type": "Consumption", "retailPrice": 0.1912, "productName": "Dasv7 Series",
         "meterName": "D4as v7", "unitOfMeasure": "1 Hour"},
    ]
    route = respx.get(RETAIL).mock(return_value=httpx.Response(200, json={"Items": items}))

    async def run():
        async with httpx.AsyncClient() as http:
            prices = RetailPrices(http)
            first = await prices.vm("Standard_D4as_v7", "francecentral")
            second = await prices.vm("Standard_D4as_v7", "francecentral")
            return first, second

    assert asyncio.run(run()) == (0.1912, 0.1912)
    assert route.call_count == 1  # le second appel vient du cache


@respx.mock
def test_unknown_meter_returns_none():
    respx.get(RETAIL).mock(return_value=httpx.Response(200, json={"Items": []}))

    async def run():
        async with httpx.AsyncClient() as http:
            return await RetailPrices(http).public_ip("francecentral")

    assert asyncio.run(run()) is None


@respx.mock
def test_model_token_prices():
    def answer(request):
        meter = request.url.params["$filter"].split("meterName eq '")[1].rstrip("'")
        price = {"5.4 mini Inp Dz 1M Tokens": 0.7406, "5.4 mini Opt Dz 1M Tokens": 4.4436,
                 "5.4 mini cd Inp Dz 1M Tokens": 0.0741}[meter]
        return httpx.Response(200, json={"Items": [
            {"type": "Consumption", "retailPrice": price, "unitOfMeasure": "1M"}]})

    respx.get(RETAIL).mock(side_effect=answer)

    async def run():
        async with httpx.AsyncClient() as http:
            return await RetailPrices(http).model_tokens("5.4 mini", "francecentral")

    assert asyncio.run(run()) == {"input": 0.7406, "output": 4.4436, "cached_input": 0.0741}

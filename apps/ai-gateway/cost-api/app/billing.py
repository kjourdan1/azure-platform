"""Coût facturé (Cost Management) des subscriptions visibles par l'identité du service.

Cost Management publie la consommation avec 8 à 24 h de retard : ces chiffres sont exacts
mais jamais « en direct ». Le coût en direct vient de inventory.py.
"""

import asyncio
from collections import defaultdict
from datetime import date, timedelta

from .arm import ArmClient

API = "2023-11-01"
WINDOW_DAYS = 30


async def subscriptions(arm: ArmClient) -> list[dict]:
    data = await arm.request("GET", "/subscriptions?api-version=2022-12-01")
    return sorted(
        ({"id": s["subscriptionId"], "name": s["displayName"]}
         for s in data.get("value", []) if s.get("state") == "Enabled"),
        key=lambda s: s["name"],
    )


def _rows(result: dict) -> list[dict]:
    """Lignes de la réponse Cost Management, indexées par nom de colonne."""
    props = result.get("properties", {})
    names = [c["name"] for c in props.get("columns", [])]
    return [dict(zip(names, row)) for row in props.get("rows", [])]


async def _query(arm: ArmClient, subscription_id: str, start: date, end: date) -> list[dict]:
    body = {
        "type": "ActualCost",
        "timeframe": "Custom",
        "timePeriod": {"from": start.isoformat(), "to": end.isoformat()},
        "dataset": {
            "granularity": "Daily",
            "aggregation": {"cost": {"name": "Cost", "function": "Sum"}},
            "grouping": [{"type": "Dimension", "name": "ServiceName"}],
        },
    }
    path = f"/subscriptions/{subscription_id}/providers/Microsoft.CostManagement/query?api-version={API}"
    return _rows(await arm.request("POST", path, json=body))


def _day(value) -> str:
    text = str(value)  # UsageDate : entier AAAAMMJJ
    return f"{text[:4]}-{text[4:6]}-{text[6:8]}"


async def billed(arm: ArmClient, today: date) -> dict:
    start = today - timedelta(days=WINDOW_DAYS - 1)
    month_start = today.replace(day=1)
    subs = await subscriptions(arm)

    daily: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    mtd_by_sub: dict[str, float] = defaultdict(float)
    mtd_by_service: dict[str, float] = defaultdict(float)
    currency = "EUR"
    last_day = None

    for index, sub in enumerate(subs):
        if index:
            await asyncio.sleep(1)  # étale les appels : quota Cost Management par locataire
        for row in await _query(arm, sub["id"], start, today):
            day = _day(row["UsageDate"])
            cost = float(row.get("Cost", 0))
            currency = row.get("Currency", currency)
            daily[day][sub["name"]] += cost
            if cost > 0:
                last_day = max(last_day or day, day)
            if day >= month_start.isoformat():
                mtd_by_sub[sub["name"]] += cost
                mtd_by_service[row.get("ServiceName") or "Autre"] += cost

    days = [(start + timedelta(days=i)).isoformat() for i in range(WINDOW_DAYS)]
    services = sorted(mtd_by_service.items(), key=lambda kv: kv[1], reverse=True)
    top, rest = services[:6], sum(v for _, v in services[6:])
    if rest > 0:
        top.append(("Autres services", rest))

    return {
        "currency": currency,
        "data_through": last_day,
        "month_to_date": round(sum(mtd_by_sub.values()), 4),
        "subscriptions": [{"name": s["name"], "month_to_date": round(mtd_by_sub[s["name"]], 4)} for s in subs],
        "services": [{"name": n, "month_to_date": round(v, 4)} for n, v in top],
        "daily": [
            {"date": d, "by_subscription": {s["name"]: round(daily[d][s["name"]], 4) for s in subs}}
            for d in days
        ],
    }

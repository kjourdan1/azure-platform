import asyncio
from datetime import date

from app import billing
from tests.fakes import FakeArm

COLUMNS = [{"name": "Cost"}, {"name": "UsageDate"}, {"name": "ServiceName"}, {"name": "Currency"}]


def _cost(rows):
    return {"properties": {"columns": COLUMNS, "rows": rows}}


def test_billed_aggregates_subscriptions_days_and_services():
    responses = {
        "aaa": _cost([[1.40, 20261028, "Virtual Machines", "EUR"], [0.15, 20261101, "Container Registry", "EUR"],
                      [0.20, 20261102, "Virtual Machines", "EUR"]]),
        "bbb": _cost([[0.64, 20261026, "Microsoft Defender for Cloud", "EUR"]]),
    }
    arm = FakeArm({
        "/subscriptions?": {"value": [
            {"subscriptionId": "bbb", "displayName": "azpl-management", "state": "Enabled"},
            {"subscriptionId": "aaa", "displayName": "azpl-lz-aks", "state": "Enabled"},
            {"subscriptionId": "ccc", "displayName": "old", "state": "Disabled"},
        ]},
        "/subscriptions/": lambda path, body: responses[path.split("/")[2]],
    })

    result = asyncio.run(billing.billed(arm, date(2026, 11, 3)))

    assert [s["name"] for s in result["subscriptions"]] == ["azpl-lz-aks", "azpl-management"]
    # Mois en cours seulement : les coûts d'octobre restent dans la série quotidienne.
    assert result["month_to_date"] == 0.35
    assert result["subscriptions"][0]["month_to_date"] == 0.35
    assert result["subscriptions"][1]["month_to_date"] == 0
    assert result["services"][0] == {"name": "Virtual Machines", "month_to_date": 0.2}
    assert len(result["daily"]) == 30
    oct28 = next(d for d in result["daily"] if d["date"] == "2026-10-28")
    assert oct28["by_subscription"] == {"azpl-lz-aks": 1.4, "azpl-management": 0}
    assert result["data_through"] == "2026-11-02"
    # La subscription désactivée n'est jamais interrogée.
    assert not any("/ccc/" in path for _, path, _ in arm.calls)


def test_billed_query_is_daily_by_service():
    arm = FakeArm({
        "/subscriptions?": {"value": [{"subscriptionId": "aaa", "displayName": "x", "state": "Enabled"}]},
        "/subscriptions/": _cost([]),
    })
    asyncio.run(billing.billed(arm, date(2026, 11, 3)))
    body = arm.calls[1][2]
    assert body["dataset"]["granularity"] == "Daily"
    assert body["timePeriod"] == {"from": "2026-10-05", "to": "2026-11-03"}

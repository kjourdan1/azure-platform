from fastapi.testclient import TestClient

from app import main
from tests.fakes import FakeArm, FakePrices


def _client(monkeypatch, arm, prices=None):
    monkeypatch.setattr(main, "ArmClient", lambda http: arm)
    monkeypatch.setattr(main, "RetailPrices", lambda http: prices or FakePrices())
    return TestClient(main.app)


def test_healthz(monkeypatch):
    with _client(monkeypatch, FakeArm({})) as client:
        assert client.get("/healthz").json() == {"status": "ok"}


def test_live_envelope(monkeypatch):
    arm = FakeArm({"/providers/Microsoft.ResourceGraph": {"data": []}})
    with _client(monkeypatch, arm) as client:
        body = client.get("/api/cost/live").json()
    assert body["hourly"] == 0
    assert body["stale"] is False
    assert body["refresh_seconds"] == 60


def test_source_down_on_first_load_is_503(monkeypatch):
    class DownArm(FakeArm):
        async def request(self, *args, **kwargs):
            raise ConnectionError("down")

    with _client(monkeypatch, DownArm({})) as client:
        response = client.get("/api/cost/billed")
    assert response.status_code == 503
    assert "ConnectionError" in response.json()["detail"]


def test_model_prices(monkeypatch):
    class Prices(FakePrices):
        async def model_tokens(self, meter, region):
            return {"input": 0.7406, "output": 4.4436, "cached_input": 0.0741}

    with _client(monkeypatch, FakeArm({}), Prices()) as client:
        body = client.get("/api/cost/model-prices").json()
    assert body["per_million"]["output"] == 4.4436
    assert body["meter"] == "5.4 mini"

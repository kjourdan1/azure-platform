import asyncio

import pytest

from app import inventory
from tests.fakes import FakeArm, FakePrices


def _graph(rows):
    return FakeArm({"/providers/Microsoft.ResourceGraph": {"data": rows}})


def _row(**kw):
    base = {"name": "r", "location": "francecentral", "resourceGroup": "rg", "subscription": "azpl-lz-aks"}
    return {**base, **kw}


def test_running_cluster_is_priced_per_node():
    arm = _graph([
        _row(name="aks-system", type="microsoft.compute/virtualmachinescalesets",
             resourceGroup="MC_rg_aks_francecentral", skuName="Standard_D4as_v7", capacity=2,
             osDiskType="Premium_LRS", osDiskSize=30),
        _row(name="kubernetes", type="microsoft.network/loadbalancers", skuName="Standard", lbRules=2),
        _row(name="ip", type="microsoft.network/publicipaddresses", skuName="Standard"),
        _row(name="aks", type="microsoft.containerservice/managedclusters", skuTier="Free"),
    ])
    result = asyncio.run(inventory.live(arm, FakePrices()))

    nodes = result["items"][0]
    assert nodes["category"] == "Nœuds AKS"
    assert nodes["detail"] == "2 × Standard_D4as_v7"
    assert nodes["hourly"] == round(2 * (0.1912 + 5.7345 / 730), 5)
    assert result["cluster_running"] is True
    assert result["hourly"] == round(nodes["hourly"] + 0.0224 + 0.0045, 4)
    assert result["monthly"] == pytest.approx(result["hourly"] * 730, abs=0.01)


def test_idle_platform_has_only_permanent_costs():
    arm = _graph([
        _row(name="acr", type="microsoft.containerregistry/registries", skuName="Basic"),
        _row(name="lab.example", type="microsoft.network/dnszones"),
        _row(name="lb-empty", type="microsoft.network/loadbalancers", skuName="Standard", lbRules=0),
    ])
    result = asyncio.run(inventory.live(arm, FakePrices()))
    assert result["cluster_running"] is False
    assert result["items"][2]["hourly"] == 0.0
    assert abs(result["daily"] - (0.1496 + 0.4489 / 730 * 24)) < 0.001


def test_unpriced_resource_is_not_guessed():
    arm = _graph([_row(name="d", type="microsoft.compute/disks", skuName="StandardSSD_LRS", diskSize=64)])
    result = asyncio.run(inventory.live(arm, FakePrices()))
    assert result["items"][0]["hourly"] is None
    assert result["hourly"] == 0

"""These are exactly the checks CI runs on every PR."""
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_version():
    resp = client.get("/version")
    assert resp.status_code == 200
    assert resp.json() == {"version": "1.0.0"}


def test_read_item_ok():
    resp = client.get("/items/1")
    assert resp.status_code == 200
    body = resp.json()
    assert body["item_id"] == 1
    assert body["name"] == "Widget"


def test_read_item_not_found():
    resp = client.get("/items/999")
    assert resp.status_code == 404
    assert resp.json()["detail"] == "Item not found"

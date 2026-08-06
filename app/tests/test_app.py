"""Unit tests for the sample service, run by the CI pipeline before build."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root():
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.json()
    assert body["service"] == "gitops-cicd-demo"
    assert "version" in body


def test_healthz():
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_info_has_expected_fields():
    resp = client.get("/api/info")
    assert resp.status_code == 200
    body = resp.json()
    for key in ("hostname", "version", "git_sha"):
        assert key in body


def test_unknown_route_404():
    assert client.get("/does-not-exist").status_code == 404

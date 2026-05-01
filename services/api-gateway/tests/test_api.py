import pytest
from unittest.mock import MagicMock, patch
from src.app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"
    assert data["service"] == "api-gateway"


def test_create_event(client):
    mock_metadata = MagicMock()
    mock_metadata.offset    = 42
    mock_metadata.partition = 0

    mock_future = MagicMock()
    mock_future.get.return_value = mock_metadata

    mock_producer = MagicMock()
    mock_producer.send_event.return_value = mock_future
    mock_producer.is_connected.return_value = True

    with patch("src.app.get_producer", return_value=mock_producer):
        response = client.post(
            "/api/events",
            json={"user_id": "u1", "event_type": "click", "payload": {"page": "home"}},
        )

    assert response.status_code == 201
    body = response.get_json()
    assert body["event_id"]  == "42"
    assert body["offset"]    == 42
    assert body["partition"] == 0


def test_create_event_missing_fields(client):
    """Request missing event_type should return 400."""
    response = client.post("/api/events", json={"user_id": "u1"})
    assert response.status_code == 400
    assert "Missing required fields" in response.get_json()["error"]


def test_create_event_empty_body(client):
    """Empty body should return 400."""
    response = client.post("/api/events", json={})
    assert response.status_code == 400


def test_metrics_endpoint(client):
    """Prometheus /metrics should return 200 with text/plain content."""
    response = client.get("/metrics")
    assert response.status_code == 200
    assert b"http_requests_total" in response.data
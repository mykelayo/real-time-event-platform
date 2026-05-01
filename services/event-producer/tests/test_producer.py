import time
import threading
from unittest.mock import MagicMock, patch
from src.kafka_client import KafkaClient


def _make_client():
    """
    Build a KafkaClient with the KafkaProducer patched out so no real
    broker connection is attempted.
    """
    mock_producer = MagicMock()

    mock_metadata = MagicMock()
    mock_metadata.partition = 0
    mock_metadata.offset    = 0

    mock_future = MagicMock()
    mock_future.get.return_value = mock_metadata
    mock_producer.send.return_value = mock_future

    with patch("src.kafka_client.KafkaProducer", return_value=mock_producer):
        client = KafkaClient()

    return client, mock_producer


def test_generate_event_shape():
    client, _ = _make_client()
    event = client._generate_event()

    assert "user_id"    in event
    assert "event_type" in event
    assert "payload"    in event
    assert "timestamp"  in event
    assert event["event_type"] in ["page_view", "click", "purchase", "signup", "logout"]


def test_run_sends_events():
    """run() should call producer.send() at least once within the interval window."""
    client, mock_producer = _make_client()
    client.interval = 0.05   

    t = threading.Thread(target=client.run, daemon=True)
    t.start()
    time.sleep(0.25)          
    client._running = False
    t.join(timeout=2)

    assert mock_producer.send.call_count >= 1


def test_shutdown_flushes_producer():
    """When _running is already False, run() should flush and close cleanly."""
    client, mock_producer = _make_client()
    client.interval = 0.05
    client._running = False   

    client.run()

    mock_producer.flush.assert_called_once()
    mock_producer.close.assert_called_once()
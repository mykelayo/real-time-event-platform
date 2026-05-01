import json
from unittest.mock import MagicMock, patch
from src.processor import StreamProcessor


def _make_processor():
    """
    Build a StreamProcessor with all external I/O mocked out:
    - KafkaConsumer  (no broker needed)
    - redis.Redis    (no Redis server needed)
    - init_schema    (no Postgres needed)
    - db_client._get_pool (prevents pool creation on import)
    """
    mock_consumer = MagicMock()
    mock_redis    = MagicMock()

    with patch("src.processor.KafkaConsumer", return_value=mock_consumer), \
         patch("src.processor.redis.Redis",   return_value=mock_redis), \
         patch("src.processor.init_schema"), \
         patch("src.db_client._get_pool"):
        processor = StreamProcessor()

    processor.consumer = mock_consumer
    processor.redis    = mock_redis
    return processor, mock_consumer, mock_redis

def test_process_calls_save_and_cache():
    """process() must delegate to both _save_to_db and _update_cache."""
    processor, _, _ = _make_processor()

    event = {
        "user_id":    "user_1",
        "event_type": "click",
        "payload":    {"page": "home"},
        "timestamp":  "2026-01-01T00:00:00",
    }

    with patch.object(processor, "_save_to_db")  as mock_save, \
         patch.object(processor, "_update_cache") as mock_cache:
        processor.process(event)

    mock_save.assert_called_once_with(event)
    mock_cache.assert_called_once_with(event)


def test_process_continues_if_redis_fails():
    """A Redis failure inside _update_cache must not crash process()."""
    processor, _, mock_redis = _make_processor()
    mock_redis.incr.side_effect = Exception("Redis connection lost")

    event = {
        "user_id":    "user_1",
        "event_type": "click",
        "payload":    {},
        "timestamp":  "2026-01-01T00:00:00",
    }

    # Should not raise
    with patch.object(processor, "_save_to_db"):
        processor.process(event)

def test_update_cache_increments_correct_key():
    processor, _, mock_redis = _make_processor()

    processor._update_cache({"event_type": "purchase"})

    mock_redis.incr.assert_called_once_with("event_count:purchase")


def test_update_cache_unknown_event_type():
    """Missing event_type key should fall back to 'unknown'."""
    processor, _, mock_redis = _make_processor()

    processor._update_cache({})   # no event_type key

    mock_redis.incr.assert_called_once_with("event_count:unknown")

def test_run_skips_bad_message_and_continues():
    """
    A single bad message (one that raises inside process()) must not
    crash the consumer loop; consumer.close() must still be called.
    """
    processor, mock_consumer, _ = _make_processor()

    bad_message        = MagicMock()
    bad_message.value  = {"event_type": "click", "user_id": "u1"}
    bad_message.offset = 0

    call_count = 0

    def poll_side_effect(**kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return {"tp1": [bad_message]}
        # Stop the loop on the second poll
        processor._running = False
        return {}

    mock_consumer.poll.side_effect = poll_side_effect

    with patch.object(processor, "process", side_effect=Exception("db error")):
        processor.run()

    mock_consumer.close.assert_called_once()


def test_run_commits_after_successful_process():
    """A successfully processed message should trigger consumer.commit()."""
    processor, mock_consumer, _ = _make_processor()

    good_message        = MagicMock()
    good_message.value  = {
        "user_id":    "u1",
        "event_type": "signup",
        "payload":    {},
        "timestamp":  "2026-01-01T00:00:00",
    }
    good_message.offset = 1

    call_count = 0

    def poll_side_effect(**kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return {"tp1": [good_message]}
        processor._running = False
        return {}

    mock_consumer.poll.side_effect = poll_side_effect

    with patch.object(processor, "_save_to_db"), \
         patch.object(processor, "_update_cache"):
        processor.run()

    mock_consumer.commit.assert_called_once()
    mock_consumer.close.assert_called_once()
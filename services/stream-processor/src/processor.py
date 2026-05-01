import os
import json
import time
from datetime import datetime
import signal
import logging
import redis
from kafka import KafkaConsumer
from kafka.errors import NoBrokersAvailable
from src.db_client import get_connection, put_connection, init_schema

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)


class StreamProcessor:
    def __init__(self):
        self.topic    = os.getenv("KAFKA_TOPIC", "user-events")
        self.servers  = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "event-cluster-kafka-bootstrap.kafka:9092")
        self.consumer = None
        self._running = True

        # Redis client for caching per-event-type counts
        self.redis = redis.Redis(
            host=os.getenv("REDIS_HOST", "redis"),
            port=int(os.getenv("REDIS_PORT", "6379")),
            decode_responses=True,
        )

        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT,  self._handle_shutdown)

        # Ensure the DB table exists before we start consuming
        init_schema()
        self._connect_with_retry()

    def _connect_with_retry(self, max_retries=10, backoff=3):
        for attempt in range(1, max_retries + 1):
            try:
                self.consumer = KafkaConsumer(
                    self.topic,
                    bootstrap_servers=self.servers,
                    value_deserializer=lambda m: json.loads(m.decode("utf-8")),
                    group_id="stream-processor-group",
                    auto_offset_reset="earliest",
                    enable_auto_commit=False,
                )
                log.info("Connected to Kafka at %s", self.servers)
                return
            except NoBrokersAvailable:
                log.warning(
                    "Kafka not available (attempt %d/%d), retrying in %ds...",
                    attempt, max_retries, backoff
                )
                time.sleep(backoff)

        raise RuntimeError(f"Could not connect to Kafka after {max_retries} attempts")

    def run(self):
        log.info("Stream processor running (topic=%s)", self.topic)
        while self._running:
            records = self.consumer.poll(timeout_ms=1000)
            for topic_partition, messages in records.items():
                for message in messages:
                    try:
                        self.process(message.value)
                        self.consumer.commit()
                    except Exception as e:
                        log.error(
                            "Failed to process message at offset %d: %s",
                            message.offset, e
                        )

        self.consumer.close()
        log.info("Consumer closed cleanly")

    def process(self, event):
        """Persist the event to Postgres and increment its Redis counter."""
        log.info("Processing event type=%s user=%s", event.get("event_type"), event.get("user_id"))
        self._save_to_db(event)
        try:
            self._update_cache(event)
        except Exception as e:
            log.warning("Redis cache update failed, continuing: %s", e)

    def _save_to_db(self, event):
        conn = get_connection()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO events (user_id, event_type, payload, timestamp)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (
                        event.get("user_id"),
                        event.get("event_type"),
                        json.dumps(event.get("payload", {})),
                        event.get("timestamp", datetime.utcnow().isoformat()),
                    )
                )
            conn.commit()
        finally:
            put_connection(conn)

    def _update_cache(self, event):
        "Increment a Redis counter for each event type"
        event_type = event.get("event_type", "unknown")
        key = f"event_count:{event_type}"
        self.redis.incr(key)
        log.debug("Incremented Redis key %s", key)

    def _handle_shutdown(self, signum, frame):
        log.info("Shutdown signal received, stopping consumer loop...")
        self._running = False
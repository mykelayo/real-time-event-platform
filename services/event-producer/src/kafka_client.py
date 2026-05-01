import os
import json
import time
import random
import signal
import logging
from datetime import datetime, timezone
from kafka import KafkaProducer
from kafka.errors import NoBrokersAvailable

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

EVENT_TYPES = ["page_view", "click", "purchase", "signup", "logout"]
USER_IDS    = [f"user_{i}" for i in range(1, 21)]


class KafkaClient:
    def __init__(self):
        self.bootstrap_servers = os.getenv(
            "KAFKA_BOOTSTRAP_SERVERS",
            "event-cluster-kafka-bootstrap.kafka:9092"
        )
        self.topic    = os.getenv("KAFKA_TOPIC", "user-events")
        self.interval = float(os.getenv("PRODUCE_INTERVAL_SECONDS", "1.0"))
        self.producer = None
        self._running = True

        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT,  self._handle_shutdown)

        self._connect_with_retry()

    def _connect_with_retry(self, max_retries=10, backoff=3):
        for attempt in range(1, max_retries + 1):
            try:
                self.producer = KafkaProducer(
                    bootstrap_servers=self.bootstrap_servers,
                    value_serializer=lambda v: json.dumps(v).encode("utf-8"),
                    acks="all",
                    retries=3,
                    max_in_flight_requests_per_connection=5,
                    compression_type="gzip",
                )
                log.info("Connected to Kafka at %s", self.bootstrap_servers)
                return
            except NoBrokersAvailable:
                log.warning(
                    "Kafka not available (attempt %d/%d), retrying in %ds...",
                    attempt, max_retries, backoff
                )
                time.sleep(backoff)

        raise RuntimeError(f"Could not connect to Kafka after {max_retries} attempts")

    def run(self):
        log.info("Event producer running (topic=%s, interval=%.1fs)", self.topic, self.interval)
        while self._running:
            try:
                event    = self._generate_event()
                future   = self.producer.send(self.topic, value=event)
                metadata = future.get(timeout=10)
                log.info(
                    "Sent event type=%s user=%s → partition=%d offset=%d",
                    event["event_type"], event["user_id"],
                    metadata.partition, metadata.offset
                )
            except Exception as e:
                log.error("Failed to send event: %s", e)

            time.sleep(self.interval)

        if self.producer:
            self.producer.flush()
            self.producer.close()
            log.info("Producer closed cleanly")

    def _generate_event(self):
        return {
            "user_id":    random.choice(USER_IDS),
            "event_type": random.choice(EVENT_TYPES),
            "payload":    {"source": "event-producer"},
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

    def _handle_shutdown(self, signum, frame):
        log.info("Shutdown signal received, stopping producer loop...")
        self._running = False
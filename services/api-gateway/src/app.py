import os
import socket
from dataclasses import asdict
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
from src.models.event import Event
from src.producers.event_producer import EventProducer

app = Flask(__name__)
CORS(app)

REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
EVENT_COUNT   = Counter('events_produced_total', 'Total events produced', ['event_type'])

# Lazily initialised — not created until the first request, so the app
# starts cleanly even if Kafka isn't up yet.
_producer = None

def get_producer():
    global _producer
    if _producer is None:
        _producer = EventProducer()
    return _producer

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy",
        "service": "api-gateway",
        "timestamp": datetime.now().isoformat(),
        "pod": socket.gethostname()
    }), 200

@app.route('/metrics')
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/api/events', methods=['POST'])
def create_event():
    try:
        data = request.get_json()
        if not data or 'user_id' not in data or 'event_type' not in data:
            return jsonify({"error": "Missing required fields: user_id, event_type"}), 400

        event = Event(
            user_id=data['user_id'],
            event_type=data['event_type'],
            payload=data.get('payload', {}),
        )

        future          = get_producer().send_event(asdict(event))
        record_metadata = future.get(timeout=10)

        EVENT_COUNT.labels(event_type=data['event_type']).inc()
        REQUEST_COUNT.labels(method='POST', endpoint='/api/events', status='201').inc()

        return jsonify({
            "message":   "Event created successfully",
            "event_id":  str(record_metadata.offset),
            "partition": record_metadata.partition,
            "offset":    record_metadata.offset
        }), 201

    except Exception as e:
        REQUEST_COUNT.labels(method='POST', endpoint='/api/events', status='500').inc()
        return jsonify({"error": str(e)}), 500

@app.route('/api/info')
def info():
    return jsonify({
        "service":         "api-gateway",
        "version":         "1.0.0",
        "pod_name":        socket.gethostname(),
        "pod_ip":          socket.gethostbyname(socket.gethostname()),
        "kafka_connected": get_producer().is_connected()
    })

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port)
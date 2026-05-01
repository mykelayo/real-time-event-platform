import os
import logging
from psycopg2 import pool

log = logging.getLogger(__name__)

_pool = None


def _get_pool():
    global _pool
    if _pool is None:
        _pool = pool.SimpleConnectionPool(
            minconn=1,
            maxconn=10,
            host=os.getenv("POSTGRES_HOST", "localhost"),
            database=os.getenv("POSTGRES_DB", "eventdb"),
            user=os.getenv("POSTGRES_USER"),
            password=os.getenv("POSTGRES_PASSWORD"),
        )
        log.info("Postgres connection pool created")
    return _pool


def get_connection():
    """Borrow a connection from the pool. Caller must call put_connection() when done."""
    return _get_pool().getconn()


def put_connection(conn):
    """Return a connection to the pool."""
    _get_pool().putconn(conn)


def init_schema():

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS events (
                    id         SERIAL PRIMARY KEY,
                    user_id    VARCHAR(255) NOT NULL,
                    event_type VARCHAR(100) NOT NULL,
                    payload    JSONB        NOT NULL DEFAULT '{}',
                    timestamp  TIMESTAMPTZ  NOT NULL,
                    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
                )
            """)
            # Index on event_type makes aggregation queries fast
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_events_event_type
                ON events (event_type)
            """)
        conn.commit()
        log.info("Schema initialised")
    finally:
        put_connection(conn)
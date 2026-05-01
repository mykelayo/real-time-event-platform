#!/bin/bash
set -euo pipefail

BASE_URL="${1:-http://localhost:5000}"
TOTAL=100
PASS=0
FAIL=0

echo "==> Running load test: $TOTAL requests against $BASE_URL"

for i in $(seq 1 "$TOTAL"); do
  PAYLOAD=$(printf '{"user_id":"user-%d","event_type":"click","payload":{"page":"home"}}' "$i")

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$BASE_URL/api/events" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  if [ "$HTTP_CODE" = "201" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL (HTTP $HTTP_CODE) on request $i"
  fi
done

echo ""
echo "Load test complete: $PASS passed, $FAIL failed out of $TOTAL requests."
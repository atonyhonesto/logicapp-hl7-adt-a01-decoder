#!/usr/bin/env bash
# Example: invoke local Logic App Standard workflow (Request trigger)
#
# NOTE: The exact local invoke URL can differ. When you start the host (F5 / func start),
# look for the Request trigger URL in the terminal output and paste it below.
#
# This script expects request.sample.json in the same folder.

set -euo pipefail

URL="${1:-http://localhost:7071/api/Hl7AdtA01ToJson/triggers/When_a_HTTP_request_is_received/invoke?api-version=2016-06-01}"

curl -sS -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d @./request.sample.json | jq .

#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${NULLHUB_URL:-http://127.0.0.1:19802}"
OUTPUT="${MISSION_CONTROL_VIDEO_OUT:-docs/demo/nullhub-mission-control-demo.mov}"
RECORD_SECONDS="${MISSION_CONTROL_RECORD_SECONDS:-36}"
DEMO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DEMO_SCRIPT_DIR/.." && pwd)"
OUTPUT_ABS="$REPO_ROOT/$OUTPUT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Mission Control video recording currently uses macOS screencapture." >&2
  echo "Run scripts/mission_control_demo.sh for the portable live demo driver." >&2
  exit 2
fi

if ! command -v screencapture >/dev/null 2>&1; then
  echo "screencapture is required for local video recording on macOS." >&2
  exit 2
fi

mkdir -p "$(dirname "$OUTPUT_ABS")"
rm -f "$OUTPUT_ABS"

node - "$BASE_URL" <<'NODE'
const base = process.argv[2].replace(/\/$/, '');
try {
  const res = await fetch(`${base}/api/mission-control/state`);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
} catch (error) {
  console.error(`Cannot reach NullHub at ${base}: ${error.message}`);
  process.exit(1);
}
NODE

echo "Recording Mission Control demo to $OUTPUT_ABS"
echo "Open UI: $BASE_URL/mission-control"
echo "If macOS asks for Screen Recording permission, allow it and rerun this script."

open "$BASE_URL/mission-control" >/dev/null 2>&1 || true
sleep 1

screencapture -v -V "$RECORD_SECONDS" -k "$OUTPUT_ABS" &
RECORDER_PID=$!

cleanup() {
  if kill -0 "$RECORDER_PID" >/dev/null 2>&1; then
    kill "$RECORDER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup INT TERM

MISSION_CONTROL_OPEN_BROWSER=0 \
MISSION_CONTROL_PREROLL_MS=2000 \
MISSION_CONTROL_FAILURE_HOLD_MS=3200 \
MISSION_CONTROL_COMPLETION_HOLD_MS=4000 \
MISSION_CONTROL_TIMEOUT_MS=50000 \
"$DEMO_SCRIPT_DIR/mission_control_demo.sh"

wait "$RECORDER_PID"
trap - INT TERM

if [[ ! -s "$OUTPUT_ABS" ]]; then
  echo "Recording did not produce a video file. Check macOS Screen Recording permission and rerun." >&2
  exit 1
fi

ls -lh "$OUTPUT_ABS"
echo "Video ready: $OUTPUT_ABS"

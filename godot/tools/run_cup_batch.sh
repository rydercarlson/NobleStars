#!/bin/zsh
# N headless Nobles Cup matches back to back with NS3_BALL_LOG on, one Godot at
# a time. NS3_BALL_LOG quits at full time, so each match costs only as long as it
# actually lasts. Local test harness; not part of the game.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
N="${N:-5}"
OUT="${OUT:-/tmp/cup_batch.log}"
BUDGET="${RUN_SECONDS:-190}"
cd "$ROOT"
: >"$OUT"
for i in $(seq 1 $N); do
  echo "===== match $i =====" >>"$OUT"
  /Applications/Godot.app/Contents/MacOS/Godot --path godot --headless >>"$OUT" 2>&1 &
  PID=$!
  SLEPT=0
  while [ $SLEPT -lt $BUDGET ]; do
    if ! kill -0 $PID 2>/dev/null; then break; fi
    sleep 2
    SLEPT=$((SLEPT+2))
  done
  kill $PID 2>/dev/null
  wait $PID 2>/dev/null
done
echo "[harness] $N matches, log at $OUT"

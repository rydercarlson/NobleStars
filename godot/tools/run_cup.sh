#!/bin/zsh
# Runs one headless Nobles Cup match in THIS worktree and kills it after a fixed
# wall-clock budget, so a results screen can never leave a Godot holding the
# import lock. Local test harness; not part of the game.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECS="${RUN_SECONDS:-190}"
OUT="${OUT:-/tmp/cup_run.log}"
cd "$ROOT"
/Applications/Godot.app/Contents/MacOS/Godot --path godot --headless >"$OUT" 2>&1 &
PID=$!
SLEPT=0
while [ $SLEPT -lt $SECS ]; do
  if ! kill -0 $PID 2>/dev/null; then break; fi
  sleep 5
  SLEPT=$((SLEPT+5))
done
kill $PID 2>/dev/null
wait $PID 2>/dev/null
echo "[harness] ran ${SLEPT}s, log at $OUT"

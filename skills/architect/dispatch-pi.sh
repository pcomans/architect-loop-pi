#!/usr/bin/env bash
# dispatch-pi.sh — self-healing single-lane `pi` dispatch wrapper.
#
# FAILURE MODE IT FIXES: a fresh `pi -p` dispatch intermittently draws a model
# connection that never streams — zero output bytes AND zero CPU used — and hangs
# until the outer timeout. It is not an outage (a low-thinking canary returns
# instantly), it's a stuck connection; the reliable recovery is to kill and
# re-dispatch with a fresh session id, which streams within seconds. This wrapper
# does that automatically so a stall doesn't cost a supervision cycle.
#
# WHAT IT DOES: launches `pi` in the background, samples output-bytes (the log)
# and /proc CPU jiffies (the pi process). If BOTH are still zero past STALL_SECS
# it kills `pi` and relaunches with a fresh "<session>-rN" id (up to MAX_RETRIES).
# Once output or CPU appears it stops watching and just waits for completion,
# bounded by an outer `timeout` (RUN_TIMEOUT). Returns pi's exit code.
#
# USAGE:
#   dispatch-pi.sh <session-id> <block-file> <out-file> [err-file] [thinking]
#
# ENV:
#   TOOLS                  if set, passed to `pi --tools "$TOOLS"` — use this to
#                          actually enforce a read-only reviewer/researcher run,
#                          e.g. TOOLS=read,grep,find,ls (without it a run routed
#                          through this wrapper gets pi's full write/edit/bash set).
#   ARCHITECT_BUILDER_MODEL  builder model (default deepseek/deepseek-v4-pro).
#   STALL_SECS=75 MAX_RETRIES=3 RUN_TIMEOUT=5400 POLL_SECS=15
#
# SCOPE: this is the SIMPLE single-checkout dispatch. For parallel worktree lanes
# use confined-pi.sh (namespace bind-mount + the same stall watch), next to this
# file. The two share an identical watch loop, kept duplicated so each script is
# self-contained and copy-pasteable; keep them in sync.
set -uo pipefail

SESSION="${1:?session-id required}"
BLOCK="${2:?block file required}"
OUT="${3:?out file required}"
ERR="${4:-${OUT%.out}.err}"
THINKING="${5:-xhigh}"
MODEL="${ARCHITECT_BUILDER_MODEL:-deepseek/deepseek-v4-pro}"
STALL_SECS="${STALL_SECS:-75}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RUN_TIMEOUT="${RUN_TIMEOUT:-5400}"
POLL_SECS="${POLL_SECS:-15}"

# optional read-only enforcement (empty-array-safe under `set -u`)
tools_arg=()
[ -n "${TOOLS:-}" ] && tools_arg=(--tools "$TOOLS")

jiffies() { awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null || echo 0; }
kill_tree() {
  local root="$1" c
  for c in $(pgrep -P "$root" 2>/dev/null); do kill_tree "$c"; done
  kill -9 "$root" 2>/dev/null
}

attempt=0
while :; do
  sid="$SESSION"; [ "$attempt" -gt 0 ] && sid="${SESSION}-r${attempt}"
  echo "[dispatch-pi] attempt $attempt: session=$sid model=$MODEL thinking=$THINKING tools=${TOOLS:-<all>}" >&2
  timeout "$RUN_TIMEOUT" pi -p --mode json --session-id "$sid" \
    --model "$MODEL" --thinking "$THINKING" "${tools_arg[@]+"${tools_arg[@]}"}" "@$BLOCK" \
    > "$OUT" 2> "$ERR" &
  pid=$!
  # Find the real pi process: the backgrounded job is a `timeout` wrapper whose
  # child is pi. (`pgrep -x pi | tail -1` would also usually work but can pick the
  # WRONG pi when several run at once — fine here because this script is
  # single-checkout only; parallel lanes use confined-pi.sh, which scopes by PID.)
  sleep 3
  pipid=$(pgrep -P "$pid" -x pi 2>/dev/null | head -1)
  [ -z "$pipid" ] && pipid=$(pgrep -x pi 2>/dev/null | tail -1)
  [ -z "$pipid" ] && pipid=$pid

  streaming=0; killed=0; waited=3; last_rc=""
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$POLL_SECS"; waited=$((waited+POLL_SECS))
    bytes=$(wc -c < "$OUT" 2>/dev/null || echo 0)
    j=$(jiffies "$pipid")
    if [ "$bytes" -gt 0 ] || [ "$j" -gt 0 ]; then streaming=1; break; fi
    if [ "$waited" -ge "$STALL_SECS" ]; then
      echo "[dispatch-pi] STALL at ${waited}s (0 bytes, 0 jiffies) — killing + retrying" >&2
      kill_tree "$pid"
      killed=1; break
    fi
  done

  if [ "$killed" = 1 ]; then
    wait "$pid" 2>/dev/null
  else
    # streaming detected (still running) OR the run already exited (e.g. a fast run)
    wait "$pid"; rc=$?
    bytes=$(wc -c < "$OUT" 2>/dev/null || echo 0)
    if [ "$streaming" = 1 ] || [ "$bytes" -gt 0 ]; then
      echo "[dispatch-pi] run finished (exit $rc) after ${waited}s" >&2
      exit $rc
    fi
    echo "[dispatch-pi] run exited at ${waited}s with no output (exit $rc) — retrying" >&2
    last_rc=$rc
  fi

  attempt=$((attempt+1))
  if [ "$attempt" -gt "$MAX_RETRIES" ]; then
    # Distinguish a genuine stall (process stayed alive past STALL_SECS, killed)
    # from a deterministic fast failure (pi exited fast non-zero with no stdout —
    # bad key / unknown model / bad flag). Only the former is an API-health stall;
    # for the latter surface the real exit code and the stderr that explains it.
    if [ -n "$last_rc" ] && [ "$last_rc" -ne 0 ]; then
      echo "[dispatch-pi] gave up after $MAX_RETRIES retries — last attempt exited fast (exit $last_rc) with no stdout; this looks like a hard failure (bad key / model / flag), not a stall. Last stderr:" >&2
      tail -n 20 "$ERR" >&2 2>/dev/null || true
      exit "$last_rc"
    fi
    echo "[dispatch-pi] gave up after $MAX_RETRIES retries (persistent stall) — check API health with a low-thinking canary" >&2
    exit 124
  fi
done

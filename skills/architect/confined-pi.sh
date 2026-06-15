#!/usr/bin/env bash
# confined-pi.sh — run a `pi` builder CONFINED to a git worktree, for parallel lanes.
#
# FAILURE MODE IT FIXES: `pi` has no sandbox, and `cd <worktree>` is NOT real
# isolation. A builder handed an absolute path (e.g. via an @block referenced by
# its absolute path, or repo paths in the prompt) can anchor to the canonical
# repo root and write OUTSIDE its worktree — into the main checkout — so two
# parallel lanes corrupt one tree. This wrapper bind-mounts the worktree OVER the
# canonical repo path inside a private user+mount namespace, so even an absolute
# /path/to/repo/... write resolves INTO the worktree; the real checkout cannot be
# touched. Each lane calls this with its OWN worktree + session id at the same
# canonical path, so lanes neither collide nor escape.
#
# It also carries the same stall watch as dispatch-pi.sh (an intermittent stuck
# model connection — 0 output bytes AND 0 CPU — kill + relaunch with a fresh
# "<sid>-rN" id). The namespace creates no PID namespace, so the inner pi is
# visible from outside; we find THIS lane's pi by walking the launched process's
# own child tree (NOT bare `pgrep -x pi`, which would match every concurrent
# lane's builder).
#
# REQUIRES isolation — refuses to run without it (a silent unconfined run is the
# very escape this script exists to prevent): `unshare` present AND unprivileged
# user namespaces enabled (/proc/sys/user/max_user_namespaces > 0).
#
# USAGE:
#   confined-pi.sh <worktree_abs> <canonical_repo_path> <block_relpath> \
#                  <session_id> <log_abs> [thinking]
#   - <block_relpath> must exist INSIDE the worktree (e.g. .architect/block.md).
#   - <log_abs> MUST be OUTSIDE <canonical_repo_path> so it stays readable from the
#     main checkout; the matching .err is derived. (.jsonl suffix expected.)
#
# ENV: TOOLS (passed to `pi --tools` if set, e.g. read,grep,find,ls for a confined
#   reviewer), ARCHITECT_BUILDER_MODEL (default deepseek/deepseek-v4-pro),
#   STALL_SECS=75 MAX_RETRIES=3 RUN_TIMEOUT=5400 POLL_SECS=15.
#
# NOTE: the watch loop is duplicated from dispatch-pi.sh on purpose, so each
# script is self-contained / copy-pasteable; keep the two in sync.
set -uo pipefail

WT="${1:?worktree abs path required}"
REPO="${2:?canonical repo path required}"
BLOCK="${3:?block relpath (inside worktree) required}"
SID="${4:?session-id required}"
LOG="${5:?log abs path (outside repo) required}"
THINK="${6:-xhigh}"
ERRLOG="${LOG%.jsonl}.err"
MODEL="${ARCHITECT_BUILDER_MODEL:-deepseek/deepseek-v4-pro}"
STALL_SECS="${STALL_SECS:-75}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RUN_TIMEOUT="${RUN_TIMEOUT:-5400}"
POLL_SECS="${POLL_SECS:-15}"

# --- preflight: refuse to run unconfined --------------------------------------
if ! command -v unshare >/dev/null 2>&1; then
  echo "[confined-pi] FATAL: \`unshare\` not found — cannot isolate the lane." >&2
  echo "             Refusing to run unconfined (that's the escape this prevents)." >&2
  exit 70
fi
maxns="$(cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo 0)"
if ! [ "$maxns" -gt 0 ] 2>/dev/null; then
  echo "[confined-pi] FATAL: unprivileged user namespaces unavailable (max_user_namespaces=$maxns)." >&2
  echo "             Enable them (sysctl user.max_user_namespaces>0) or run lanes SEQUENTIALLY in the main checkout." >&2
  exit 70
fi

# optional read-only enforcement (empty-array-safe under `set -u`)
tools_arg=()
[ -n "${TOOLS:-}" ] && tools_arg=(--tools "$TOOLS")

jiffies() { awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null || echo 0; }

# Find THIS lane's pi: the launched process is `timeout`, whose descendant (after
# unshare execs in place) is the pi process. Walk the child tree — lane-scoped,
# unlike bare `pgrep -x pi`. (`pgrep -x pi --ns <pid>` is an alternative on
# util-linux that supports it, but the tree walk needs no --ns support.)
find_inner_pi() {
  local root="$1" c
  [ "$(cat "/proc/$root/comm" 2>/dev/null)" = pi ] && { echo "$root"; return 0; }
  for c in $(pgrep -P "$root" 2>/dev/null); do
    find_inner_pi "$c" && return 0
  done
  return 1
}
kill_tree() {
  local root="$1" c
  for c in $(pgrep -P "$root" 2>/dev/null); do kill_tree "$c"; done
  kill -9 "$root" 2>/dev/null
}

attempt=0
while :; do
  sid="$SID"; [ "$attempt" -gt 0 ] && sid="${SID}-r${attempt}"
  echo "[confined-pi] attempt $attempt: session=$sid wt=$WT -> $REPO thinking=$THINK tools=${TOOLS:-<all>}" >&2
  # Build the inner pi command (TOOLS may be empty). The bind-mount lives only in
  # this namespace and is torn down automatically when the process tree exits.
  pi_cmd=(pi -p --mode json --session-id "$sid" --model "$MODEL" --thinking "$THINK"
          "${tools_arg[@]+"${tools_arg[@]}"}" "@$BLOCK")
  timeout "$RUN_TIMEOUT" unshare -Urm --map-root-user bash -c '
    mount --bind "$1" "$2" || exit 71
    cd "$2" || exit 72
    shift 2
    exec "$@"
  ' _ "$WT" "$REPO" "${pi_cmd[@]}" > "$LOG" 2> "$ERRLOG" &
  pid=$!

  sleep 3
  pipid="$(find_inner_pi "$pid" || true)"; [ -z "$pipid" ] && pipid="$pid"

  streaming=0; killed=0; waited=3; last_rc=""
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$POLL_SECS"; waited=$((waited+POLL_SECS))
    # re-resolve the pi pid in case it wasn't up yet on the first probe
    [ "$pipid" = "$pid" ] && pipid="$(find_inner_pi "$pid" || echo "$pid")"
    bytes=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    j=$(jiffies "$pipid")
    if [ "$bytes" -gt 0 ] || [ "$j" -gt 0 ]; then streaming=1; break; fi
    if [ "$waited" -ge "$STALL_SECS" ]; then
      echo "[confined-pi] STALL at ${waited}s (0 bytes, 0 jiffies) — killing lane + retrying" >&2
      kill_tree "$pid"
      killed=1; break
    fi
  done

  if [ "$killed" = 1 ]; then
    wait "$pid" 2>/dev/null
  else
    # streaming detected (still running) OR the run already exited (e.g. a fast run)
    wait "$pid"; rc=$?
    bytes=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    if [ "$streaming" = 1 ] || [ "$bytes" -gt 0 ]; then
      echo "[confined-pi] run finished (exit $rc) after ${waited}s" >&2
      exit $rc
    fi
    echo "[confined-pi] run exited at ${waited}s with no output (exit $rc) — retrying" >&2
    last_rc=$rc
  fi

  attempt=$((attempt+1))
  if [ "$attempt" -gt "$MAX_RETRIES" ]; then
    # Distinguish a genuine stall (process stayed alive past STALL_SECS, killed)
    # from a deterministic fast failure (pi exited fast non-zero with no stdout —
    # bad key / unknown model / bad flag). Only the former is an API-health stall;
    # for the latter surface the real exit code and the stderr that explains it.
    if [ -n "$last_rc" ] && [ "$last_rc" -ne 0 ]; then
      echo "[confined-pi] gave up after $MAX_RETRIES retries — last attempt exited fast (exit $last_rc) with no stdout; this looks like a hard failure (bad key / model / flag), not a stall. Last stderr:" >&2
      tail -n 20 "$ERRLOG" >&2 2>/dev/null || true
      exit "$last_rc"
    fi
    echo "[confined-pi] gave up after $MAX_RETRIES retries (persistent stall) — check API health with a low-thinking canary" >&2
    exit 124
  fi
done

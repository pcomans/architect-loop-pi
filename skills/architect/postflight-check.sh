#!/usr/bin/env bash
# postflight-check.sh — mechanical post-flight checks for a finished builder lane.
#
# Automates the objective Phase-6 checks the architect otherwise runs by hand (and
# can skip one of): gates untampered, no builder commits, only declared files
# touched, no stray files. These are necessary-not-sufficient — the architect
# still reads the diff against spec intent and runs the gate commands itself; this
# only catches the mechanical violations.
#
# USAGE:
#   postflight-check.sh <freeze-sha> <worktree-dir> <lane-branch> [declared-glob ...]
#
#   declared-glob: bash patterns for files the lane was allowed to touch, e.g.
#     "src/<area>/*" "docs/lanes/<slice>-<lane>.md". Patterns use bash matching, so `*`
#     spans '/' (a subtree glob like "src/<area>/*" matches nested files too).
#
# ENV: GATES_DIR (default "docs/gates") — the frozen-gates path to tamper-check.
#
# Prints PASS/FAIL per check; exits non-zero if any check fails.
set -uo pipefail

FREEZE="${1:?freeze sha required}"
WT="${2:?worktree dir required}"
BRANCH="${3:?lane branch required}"
shift 3 || true
GLOBS=("$@")
GATES_DIR="${GATES_DIR:-docs/gates}"

git -C "$WT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "FATAL: $WT is not a git working tree" >&2; exit 2; }

fails=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails+1)); }

matches_any() {  # $1=path ; returns 0 if it matches any declared glob
  local p="$1" g
  for g in "${GLOBS[@]+"${GLOBS[@]}"}"; do
    # shellcheck disable=SC2053
    [[ "$p" == $g ]] && return 0
  done
  return 1
}

# 1. Gates untampered ----------------------------------------------------------
gate_diff="$(git -C "$WT" diff "$FREEZE" -- "$GATES_DIR" 2>/dev/null)"
if [ -z "$gate_diff" ]; then
  pass "1. gates untampered ($GATES_DIR unchanged since $FREEZE)"
else
  fail "1. gates TAMPERED — $GATES_DIR changed since freeze:"
  git -C "$WT" diff --stat "$FREEZE" -- "$GATES_DIR" | sed 's/^/        /'
fi

# 2. No builder commits --------------------------------------------------------
commits="$(git -C "$WT" log --oneline "$FREEZE..$BRANCH" 2>/dev/null)"
if [ -z "$commits" ]; then
  pass "2. no builder commits ($FREEZE..$BRANCH empty)"
else
  fail "2. builder COMMITTED (the architect commits, not the builder):"
  echo "$commits" | sed 's/^/        /'
fi

# 3 + 4. Boundary + stray files ------------------------------------------------
# Parse porcelain; for renames take the destination path; best-effort unquote.
declare -a out_of_bounds=() strays=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  st="${line:0:2}"
  path="${line:3}"
  case "$path" in *" -> "*) path="${path##* -> }";; esac
  case "$path" in \"*\") path="${path%\"}"; path="${path#\"}";; esac
  if ! matches_any "$path"; then
    out_of_bounds+=("$path")
    case "$st" in '??'*|'??') strays+=("$path");; esac
  fi
done < <(git -C "$WT" status --porcelain 2>/dev/null)

if [ "${#GLOBS[@]}" -eq 0 ]; then
  echo "NOTE  3/4. no declared globs given — skipping boundary check (pass globs to enable)"
elif [ "${#out_of_bounds[@]}" -eq 0 ]; then
  pass "3. only declared files touched"
  pass "4. no stray/debug files"
else
  fail "3. OUT-OF-BOUNDS changes (not matching any declared glob):"
  printf '        %s\n' "${out_of_bounds[@]}"
  if [ "${#strays[@]}" -gt 0 ]; then
    fail "4. stray/untracked files outside the declared set:"
    printf '        %s\n' "${strays[@]}"
  else
    pass "4. no stray/untracked files (out-of-bounds are tracked modifications)"
  fi
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL CHECKS PASS"
  exit 0
fi
echo "$fails CHECK(S) FAILED"
exit 1

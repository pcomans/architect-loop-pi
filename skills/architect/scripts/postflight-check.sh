#!/usr/bin/env bash
# postflight-check.sh — mechanical post-flight checks for a finished builder lane.
#
# Automates the objective Phase-6 checks the architect otherwise runs by hand (and
# can skip one of): gates untampered, no builder commits, only declared files
# touched, no stray files. These are necessary-not-sufficient — the architect
# still reads the diff against spec intent and runs the gate commands itself; this
# only catches the mechanical violations.
#
# TRUST SCOPE: these checks read git state (diff/log/status) and so catch
# COOPERATIVE or accidental violations — an over-eager builder that committed,
# tampered with a gate, or wrote outside its lane. They are NOT adversarially
# sound: a compromised builder that rewrites `.git` (refs, index, history,
# hooks, excludes) can defeat them. For an adversarial guarantee, run this from
# a separate trusted checkout, or ensure the builder cannot write git metadata.
#
# USAGE:
#   postflight-check.sh <freeze-sha> <worktree-dir> <lane-branch> [declared-glob ...]
#
#   declared-glob: bash patterns for files the lane was allowed to touch, e.g.
#     "src/<area>/*" "docs/lanes/<slice>-<lane>.md". Patterns use bash matching, so `*`
#     spans '/' (a subtree glob like "src/<area>/*" matches nested files too).
#
# ENV: GATES_DIR (default "docs/gates") — the frozen-gates path to tamper-check.
#      CHECK_IGNORED=1 — also fail on gitignored stray files (off by default;
#        ignored files can't reach the merge and --ignored noises on build output).
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

# Validate the refs up front. Checks 1 and 2 below test only for EMPTY git
# output, so an unresolvable FREEZE or BRANCH (typo, missing lane branch) would
# otherwise make git error to a suppressed stderr, return empty stdout, and read
# as "gates untampered / no commits" — a vacuous PASS on the two load-bearing
# gates. Fail hard instead of certifying nothing.
for ref in "$FREEZE" "$BRANCH"; do
  git -C "$WT" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null || {
    echo "FATAL: '$ref' is not a valid commit or branch in $WT" >&2; exit 2; }
done

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
# Parse porcelain. A rename/copy reports `old -> new`: BOTH sides are touched
# (the source is deleted/moved), so check both against the declared set —
# checking only the destination lets `git mv <out-of-bounds> <in-bounds>` slip a
# write to an undeclared file past the boundary gate. Best-effort unquote.
#
# Ignored files are off by default: they can't reach the integration branch
# (the architect merges tracked changes; ignored debris dies with the throwaway
# worktree), and --ignored would false-positive on legitimate build output. Set
# CHECK_IGNORED=1 for strict hygiene — then ignored files (`!!`) count as strays.
ignored_flag=()
[ -n "${CHECK_IGNORED:-}" ] && ignored_flag=(--ignored)
unq() {  # best-effort unquote a porcelain path
  local p="$1"; case "$p" in \"*\") p="${p%\"}"; p="${p#\"}";; esac; printf '%s' "$p"
}
declare -a out_of_bounds=() strays=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  st="${line:0:2}"
  rest="${line:3}"
  case "$rest" in
    *" -> "*) paths=("$(unq "${rest%% -> *}")" "$(unq "${rest##* -> }")");;
    *)        paths=("$(unq "$rest")");;
  esac
  for path in "${paths[@]}"; do
    if ! matches_any "$path"; then
      out_of_bounds+=("$path")
      case "$st" in '??'*|'!!'*) strays+=("$path");; esac
    fi
  done
done < <(git -C "$WT" status --porcelain "${ignored_flag[@]+"${ignored_flag[@]}"}" 2>/dev/null)

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

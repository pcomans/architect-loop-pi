# Builder dispatch reference

Commands below are from `pi --help` and pi's bundled docs
(`@earendil-works/pi-coding-agent`, June 2026). pi's flags are stable, but
confirm against your installed version: run `pi --version` and ONE canary
dispatch before fanning out (the canary rule below). Facts that correct common
mistakes: pi has **no `-C`/`--cwd` flag** — `cd` into the target dir (or use a
subshell) before launching; pi has **no `-o`/output-file flag** — redirect
stdout; the prompt block is passed as `@file.md` (a file message), which avoids
the shell quote-mangling that plagues big inline prompts; thinking level is a
first-class flag (`--thinking xhigh|high|...`), so the architect's effort
vocabulary maps 1:1.

**No sandbox — read this first.** Unlike Codex's `workspace-write`, **pi has no
built-in sandbox** (pi's own security doc: *"Real isolation needs to come from
the operating system or a virtualization/container boundary"*). A pi builder can
read, write, run shell, **and reach `.git`** with the full permissions of the
process. The loop's isolation therefore comes from three things, not a sandbox:
(1) each lane runs in its own **git worktree + branch**; (2) "do not commit" is a
**builder-block rule the architect verifies post-flight** (`git log` on the lane
branch must show no builder commits); (3) the whole thing is meant to **run
inside a container/devcontainer** — see the security note in the README. The
architect still owns every merge to a shared branch, and gate tampering is still
caught by `git diff` on `docs/gates/` regardless of who can write.

**Preflight (once per environment):** run `pi --version`. Set the builder's
provider key (`DEEPSEEK_API_KEY` for the default; see "Builder-side standing
setup"). On the first dispatch in a new environment, launch ONE canary run and
confirm it starts cleanly, picks up the model, and that `@block.md` is read as
the prompt — before fanning anything out.

## The model lives in one place

Every command reads the builder model from `ARCHITECT_BUILDER_MODEL`, default
`deepseek/deepseek-v4-pro`. To switch the whole loop to another model, set that
one variable and the matching provider key — nothing else changes:

```bash
export ARCHITECT_BUILDER_MODEL="deepseek/deepseek-v4-pro"   # default
export DEEPSEEK_API_KEY="sk-..."
```

To switch providers, set the matching API key and point `ARCHITECT_BUILDER_MODEL`
at `<provider>/<model-id>`. pi recognizes several Chinese providers natively.
Rather than copy pi's tables here (they go stale per version), read them live:

- **Provider ids + the API-key env var** for each: `pi --help` (the "Environment
  Variables" block) or pi's bundled `docs/providers.md`.
- **Exact model ids** for a provider once its key is set:
  `pi --list-models <provider>` (e.g. `pi --list-models zai`) — don't guess slugs.
- Any other OpenAI-compatible endpoint (incl. a self-hosted vLLM/Ollama for code
  you can't send out) goes in `~/.pi/agent/models.json` (`docs/models.md`).

The only pi-specific fact this repo pins is the **default**: provider `deepseek`,
key `DEEPSEEK_API_KEY`. Everything else is read from the CLI.

## Canonical headless dispatch (architect-driven)

Write the builder block to a file first and pass it as `@<file>` — never as a
shell argument. Big prompt blocks contain quotes that shells mangle; `@file`
sidesteps that entirely (pi reads the file as the message).

Single-lane slice (dispatch in the main checkout):

```bash
pi -p --mode json \
  --model "${ARCHITECT_BUILDER_MODEL:-deepseek/deepseek-v4-pro}" --thinking xhigh \
  @.architect/dispatch-block.md \
  > .architect/last-run.jsonl
```

`--mode json` streams newline-delimited events to the file for liveness
monitoring; the builder's final message is the last assistant event in that
stream. The builder writes its lane report into `docs/lanes/` itself (it has the
`write`/`edit` tools) — the JSONL is telemetry, not the report.

## Worktree fan-out (2–4 lanes — the architect owns the parallelism)

One isolated worktree + one fresh `pi` per lane, all launched in parallel in the
background. pi has no working-dir flag, so each lane runs in a subshell `cd`'d
into its worktree. Lanes have file-touch sets checked for overlap from the spec;
each writes raw results to its own `docs/lanes/<slice>-<lane>.md`, so nothing
collides.

```bash
# per lane, off the freeze commit
git -C <repo-root> worktree add .architect/wt/<slice>-<NN> \
  -b lane/<slice>-<NN> <freeze-sha>

# write the lane's builder block, then dispatch (background, all lanes parallel)
( cd <repo-root>/.architect/wt/<slice>-<NN> && \
  pi -p --mode json \
    --model "${ARCHITECT_BUILDER_MODEL:-deepseek/deepseek-v4-pro}" --thinking xhigh \
    @block.md \
    > <repo-root>/.architect/wt/<slice>-<NN>.last-run.jsonl ) &
```

A worktree is a separate working directory on its own branch. Because pi has no
sandbox, a misbehaving builder *could* run `git commit` inside its worktree — so
the architect's post-flight checks `git log lane/<slice>-<NN> <freeze-sha>..` and
treats any builder commit as a lane defect (re-dispatch). Nothing reaches a
shared branch except through the architect's own merge.

### Integration (architect-only, after per-lane post-flight passes)

```bash
git -C <repo-root> checkout -b slice/<name> <freeze-sha>
# per passing lane, sequentially:
git -C <repo-root>/.architect/wt/<slice>-<NN> add -A
git -C <repo-root>/.architect/wt/<slice>-<NN> commit -m "lane <NN>: <what>"
git -C <repo-root> merge --no-ff lane/<slice>-<NN>
<run the gate commands>          # integration smoke after every merge
# cleanup:
git -C <repo-root> worktree remove .architect/wt/<slice>-<NN>
git -C <repo-root> branch -d lane/<slice>-<NN>
```

A merge conflict = the lane plan wasn't disjoint = a spec defect. Kill the
conflicting lane and re-spec; don't hand-resolve builder conflicts.

- Run in the background (multi-hour runs are normal); read
  `.architect/last-run.jsonl` and the repo state afterwards.
- Pin the model explicitly with `--model` — don't rely on pi's default provider
  (`google`); an unset model silently runs the wrong engine.
- Effort: `--thinking xhigh` default for unattended work; the architect
  downgrades routine, tightly-specified lanes to `--thinking high`.
- Same-slice follow-up (e.g. answering PHASE 0 disagreements after the human
  rules): give the run a stable handle with `--session-id <slice>-<NN>` on first
  dispatch, then resume it with
  `pi --session-id <slice>-<NN> -p @followup.md`. (`pi --continue` resumes the
  most recent session in the cwd if you didn't name it.) Never resume across
  slices — every slice gets a fresh context (a fresh `pi -p` with no
  `--continue`/`--session-id` is already a clean session).
- Cross-model note: the builder (DeepSeek) and the judge (Claude/Fable) are
  already different labs, so the architect running the gates itself is the
  cross-vendor check. For an extra adversarial pass on high-stakes slices, run a
  fresh read-only reviewer (next section).
- Add `.architect/` to the repo's `.gitignore`.
- **Builders never commit — the architect does.** Enforced by the prompt rule +
  post-flight `git log` check (above). This is load-bearing: nothing reaches a
  branch until the architect's tamper, boundary, and gate checks pass.

## Cross-model / adversarial review gate

For high-stakes slices, dispatch a fresh read-only reviewer over the integration
diff — `--tools read,grep,find,ls` strips `write`/`edit`/`bash`, so the reviewer
can inspect but not touch the repo:

```bash
git -C <repo-root> diff <freeze-sha>..slice/<name> > .architect/review-diff.patch
pi -p --tools read,grep,find,ls \
  --model "${ARCHITECT_BUILDER_MODEL:-deepseek/deepseek-v4-pro}" --thinking high \
  @.architect/review-block.md \
  > .architect/review.out
```

Calibrate the review block: *"flag only correctness / requirement / invariant
gaps with file:line evidence — no style preferences."* An uncalibrated reviewer
always finds something and spirals into gold-plating. A fresh Claude subagent
red-teaming the diff is an equally valid reviewer; pick whichever is cheaper for
the slice.

## Stall detection and rescue

A dispatched run is STALLED when its `--mode json` output file has not grown for
15+ minutes AND the last event is an in-progress `bash` tool call. Silent gaps
between events are normal model thinking; a shell command that should take
seconds sitting in flight for 15+ minutes is not.

Diagnose before killing: find the command's child under the pi PID
(pi → shell → child). Hot-spinning (high CPU) or blocked (zero CPU and none of
its expected side effects on disk) — hung either way.

Kill the NARROWEST thing: the stuck child process, not the pi run. The command
returns a failure to the builder, which adapts with its full context intact —
this rescues a run without throwing away hours of grounding. Kill the whole run
only when the builder re-enters the same hang or the worktree is broken; then
discard the lane and re-dispatch (hard rule 7).

pi runs tools as ordinary host processes, so a runaway command is a normal host
process — kill it by PID. The standing defense is the same as always: **every
potentially long command in the builder block must carry an explicit timeout**. Steer builders toward the repo's existing test fixtures
rather than hand-rolled long-running harnesses, which are the usual stall source.

## Manual alternative (human-driven)

Run `pi` interactively in the worktree and paste the builder block (or
`pi @block.md` to load it as the opening message). pi loops plan→act→test
against the block's stopping condition; use when the human wants to watch or
steer the run. Drop `-p` for the interactive TUI.

## Builder block template

```
Execute the architect spec below. Operating rules:

PHASE 0 — Before any code: reply with your plan and EVERY disagreement you have
with this spec, with reasons, citing real files in this repo. Silent compliance
is a failure. Silent scope additions are a failure. If you have no
disagreements, state what you checked before concluding the spec is sound.
Verify the named APIs/formats/versions against the live dependencies before
planning around them.

PHASE 1 — Freeze shared contracts (schemas/interfaces) in docs/ first. After
freeze they are read-only for everyone including you. The files under
docs/gates/ are read-only at all times — editing them fails the slice
regardless of results.

PHASE 2 — Build YOUR LANE ONLY: exactly the files listed in BOUNDARIES. You
are one of several parallel lane agents working in isolated worktrees; files
outside your lane belong to other agents — touching them fails your lane.
No placeholder implementations — search the codebase before implementing;
full implementations only. Verify your work by running the lane's gate
commands and record the verbatim output. Do NOT run `git commit`, `git push`,
or otherwise touch git history — the architect commits and merges after
verification; a commit from you fails the lane. Do NOT delete lock files or
escalate privileges if a git command fails; record the exact error and
continue. Give every potentially long command an explicit timeout; if a
runtime will not start in this environment, record the exact failure in your
lane report and route around it — never busy-wait or retry in a loop. When done,
write your lane report to docs/lanes/<slice>-<lane>.md with RAW results only —
tables, numbers, command output — no interpretation, no "promising". Every
status claim must be backed by a command result from this run. Keep the report
compact — tables and numbers, not prose. End it with exactly one status line:
STATUS: COMPLETE | COMPLETE_WITH_CONCERNS (list them) | BLOCKED (exact
blocker + what you tried). Verdicts belong to the architect and the
human. Persist until your lane is fully handled end-to-end; do not stop at
analysis or partial fixes.

=== OBJECTIVE (and why) ===
...

=== OUTPUT FORMAT ===
...

=== TOOL GUIDANCE (verification commands; verify-against-reality list) ===
...

=== BOUNDARIES (may touch / must not touch / out of scope) ===
...

=== DISAGREEMENT RULINGS (from last session) ===
...

=== ACCEPTANCE GATES (frozen at docs/gates/<slice>.md — read-only) ===
...
```

## Builder-side standing setup (one time per machine/repo)

- Provider key in the environment: `DEEPSEEK_API_KEY` for the default model
  (`deepseek/deepseek-v4-pro`). pi reads provider keys from env vars; natively
  recognized providers (`pi --help`) need no models.json entry. Any other
  OpenAI-compatible endpoint goes in `~/.pi/agent/models.json`.
- Optional `~/.pi/agent/settings.json` default model, but the loop pins
  `--model` per dispatch so it never depends on session defaults.
- Repo `AGENTS.md`: exact build/test commands and repo gotchas only — the
  loop's PHASE rules stay in the dispatch block so they version with the skill.
  pi loads `AGENTS.md`/`CLAUDE.md` as standing context by default.
- **Billing is per-token on the provider's API key** (metered), not a flat-rate
  subscription — but cheap enough that builder tokens aren't a constraint (size
  slices for convergence, not cost; default high effort).
- **Run in a container** (see the no-sandbox note at the top of this file).

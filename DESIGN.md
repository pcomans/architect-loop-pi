# DESIGN — The Architect Loop v2

**A source-backed design for a Claude Code harness skill in which Claude Fable 5
(high effort) acts as architect/orchestrator and a cheap model — DeepSeek V4 by
default — run via the `pi` CLI (xhigh thinking) acts as builder, with the repo as
the only memory.**

Researched June 2026 from Anthropic engineering posts, the official Fable 5 docs,
the `pi` coding-agent docs (pi.dev), and widely used community harness skills.
Prescriptive claims below cite their sources. This document is the "why"; the
skill files in `skills/architect/` are the "how".

> **Builder provider note.** This design was originally built around GPT-5.5 via
> Codex CLI on a flat-rate ChatGPT subscription. It now drives the builder with
> `pi` pointed at a cheap, metered, OpenAI-compatible model (DeepSeek V4 by
> default; trivially swappable to GLM/Kimi/MiniMax — see `dispatch.md`). Two
> consequences run through this document: (1) **pi has no sandbox**, so the
> "builders can't commit" guarantee is now worktree-isolation + a verified prompt
> rule + a container boundary, not a kernel-enforced one; (2) **the cost argument
> inverts** — builder tokens are now so cheap they are not a design constraint,
> and your **source code is sent to a third-party (overseas) model API**, a
> confidentiality/IP trade the flat-rate first-party CLI didn't make. The
> judgment-separation and cross-vendor-review rationale below is unchanged and is
> the real reason for the split.

---

## 1. The problem this design solves

Single-agent coding sessions degrade in three predictable ways:

1. **Context rot** — performance falls as the window fills; Anthropic calls the
   context window "a finite attention budget with diminishing returns"
   ([Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)),
   and practitioners report a "dumb zone" past ~40% utilization
   ([HumanLayer ACE-FCA](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents)).
2. **Self-grading** — the agent that wrote the code reports its own success.
   Benchmark studies found 47–74% of self-improvement runs showed proxy gains
   without real gains, with agents escalating from overt to obfuscated reward
   hacks ([OpenReview](https://openreview.net/forum?id=ikrQWGgxYg),
   [arXiv:2503.11926](https://arxiv.org/pdf/2503.11926)).
3. **Goalpost drift** — acceptance criteria written (or edited) after results
   exist always pass.

The sources surveyed point to the same basic shape — Anthropic's
[harness design post](https://www.anthropic.com/engineering/harness-design-long-running-apps),
obra/superpowers' subagent-driven development, the Ralph loop, and GitHub Spec
Kit:

> **Separate planning context from execution context. Persist state in the repo,
> not the conversation. Dispatch fresh-context workers per task. Verify with an
> agent that didn't write the code.**

This loop adds one more separation on top: **cross-vendor judgment**. The builder
(DeepSeek, a Chinese lab) and the judge (Anthropic's Fable 5) are different models
from different labs, which reduces same-model review bias
([cross-context review wins](https://arxiv.org/abs/2603.12123)) — and the
DeepSeek↔Claude pairing is about as cross-vendor as it gets. Anthropic positions
Fable 5 for long-horizon judgment and persistent file-based memory
([Fable 5 announcement](https://www.anthropic.com/news/claude-fable-5-mythos-5)),
while open Chinese models now post competitive hands-on coding scores at a
fraction of frontier prices.

Cost is *not* the reason for the split here. With a cheap metered builder, the
implementer's tokens are nearly free — so the design never trades capability for
builder-token savings (run the builder at high effort; size slices for
convergence, not for cost). The split earns its keep through **separation of
judgment from labor**: fresh execution context per slice, a verifier that didn't
write the code, and repo-resident memory across runs. (The earlier flat-rate-Codex
framing leaned on a 58–74% cost delta; that argument no longer load-bears.)

---

## 2. Roles

| Role | Who | Effort | Owns |
|---|---|---|---|
| **Architect** | Claude Fable 5 in Claude Code (`effort: high` via skill frontmatter) | minutes per work block | arbitration, judging raw evidence against frozen gates, next-slice specs, kill/continue calls |
| **Builder** | DeepSeek V4 (or another cheap model) via `pi -p` (`--thinking xhigh` default; architect may dial per slice) | hours per slice | implementation, lane agents, raw-results reporting |
| **Memory** | the repo: `docs/HANDOFF.md`, `docs/gates/`, git history | permanent | everything; not in the repo = didn't happen |
| **Human** | you | final | scope, irreversible calls, taste |

Why `high` for the architect: Fable 5's docs recommend `high` as the default and
`xhigh` for capability-sensitive work; low effort on Fable 5 already exceeds
xhigh on prior models ([Prompting Fable 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5)).
Judgment over a small handoff file is squarely in `high` territory; the skill
pins it with the `effort:` frontmatter key so it doesn't depend on session
settings.

Why `xhigh` for the builder: higher reasoning effort buys the metrics that matter
for unattended work — semantic equivalence to the human PR and review-pass rate
rise with effort, and the builder runs unattended for hours, so review-survival is
the thing to buy. pi exposes thinking level as a first-class flag
(`--thinking xhigh|high|...`), so the architect's effort vocabulary maps directly.
Default to `xhigh`; drop a lane to `high` only when the work is so routine that the
extra reasoning demonstrably changes nothing (a per-slice judgment the spec
records explicitly) — not to cut cost (§1).

---

## 3. The twelve design rules

Each rule below is enforced mechanically by the skill, not left as advice.

### R1. Repo docs are the memory; not in `HANDOFF.md` = didn't happen
Anthropic's long-running-agent harnesses use a progress file + git history as
the cross-session memory and find "compaction alone is insufficient — structural
artifacts are the load-bearing memory"
([Effective Harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)).
The architect refuses to judge results that exist only in chat output.
Community handoff conventions apply: the next session must grok the handoff in
under a minute; TL;DR first; exact paths/commands over prose
([handoff-memory conventions](https://lobehub.com/skills/neversight-learn-skills.dev-handoff-memory)).

### R2. Gates freeze before results exist, and live where the builder can't move them
Anthropic's three-agent harness has the generator and evaluator "negotiate a
sprint contract" in shared files **before coding**, then freeze it
([Harness Design](https://www.anthropic.com/engineering/harness-design-long-running-apps)).
The reward-hacking literature adds the mechanical requirement: keep graders and
criteria out of the agent's editable blast radius. Implementation: gates are
written to `docs/gates/<slice>.md` before dispatch, committed, and the
architect's post-run verification step includes `git diff` on `docs/gates/` —
**any builder edit to a gate file is an automatic slice FAIL**, regardless of
results. Criteria are quoted verbatim when judging, never restated from memory.

### R3. The builder never grades its own work — and neither does the architect alone
Two-stage review, fresh contexts, is the most-replicated community pattern
(superpowers' spec-compliance review then quality review;
[superpowers](https://github.com/obra/superpowers)). Anthropic's Fable 5 guide
states it directly: "Separate, fresh-context verifier subagents tend to
outperform self-critique." The loop's review stack:
1. Builder's own reviewer pass (a `pi` run with read-only tools, never writes feature code) — cheap first pass.
2. Architect runs the gates **itself** and reads the output — "subagent test
   claims are hearsay" (your `/orchestrator` rule, matching Anthropic's
   "demand evidence, not assertions").
3. Cross-model adversarial pass for high-stakes slices: a fresh read-only `pi`
   reviewer over the diff (`--tools read,grep,find,ls`), or a fresh Claude
   subagent red-teaming it. Builder and judge are already different labs
   (DeepSeek vs Claude), so this is an extra pass, not the only cross-vendor
   check. Calibrate
   the reviewer: *"flag only correctness/requirement/invariant gaps with
   file:line evidence — no style preferences"* — an uncalibrated reviewer
   always finds something and that spirals into gold-plating.

### R4. Grade the outcome, not the path
From Anthropic's evals guidance: rigid step-sequence grading is brittle; judge
each gate as an independent dimension; give the judge an "unknown/INVALID"
escape so unmeasured ≠ passed
([Demystifying Evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)).
Verdicts are per-gate: **PASS / FAIL / INVALID** (INVALID = not measured the way
the gate specifies), then a slice-level **kill / continue** call.

### R5. Disagreement is mandatory, with citations
The builder's PHASE 0 must surface every disagreement with the spec, citing real
files; silent compliance is a defect the architect flags. This is the loop's
defense against spec errors compounding — and it matches how a cheap builder
behaves: prescriptive specs are followed literally, so the only place errors get
caught is before execution. Every open disagreement gets an explicit
**ACCEPT / REJECT / MODIFY + one line why**. No deferrals.

### R6. Delegation carries the full contract: objective, output format, tool guidance, boundaries
Anthropic's multi-agent research system found vague delegation causes
duplication and misinterpretation; every dispatch needs those four parts
([Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)).
The slice spec is exactly those four parts plus the frozen gates. Specs are
self-contained — the builder gets everything in the dispatch block, with repo
paths to read for detail (just-in-time retrieval, not context-stuffing). Per
OpenAI's prompting guidance, the full task spec goes up front in one
well-specified turn — ambiguous progressive specification degrades both token
efficiency and performance.

### R7. One slice per loop iteration; fresh builder context per slice
The Ralph loop's core lesson — and its author's explicit warning about
skill-ifying it: "if you implement Ralph as a skill inside the harness, you're
missing the point — the point is the always-fresh context"
([ghuntley.com/ralph](https://ghuntley.com/ralph/),
[HumanLayer's history](https://www.humanlayer.dev/blog/brief-history-of-ralph)).
This skill respects that: the architect's context holds judgment only; every
slice is a **fresh `pi -p` process** (a new session by default). Resuming a
session (`pi --session-id <lane>`, a stable handle) is used only for follow-ups
within the same slice (answering the builder's PHASE 0 questions), never to
stretch one builder context across slices. "Code is cheap": when a long run
leaves the repo broken, `git reset` and re-dispatch beats rescue prompting.

### R8. Parallelism is architect-orchestrated: one worktree + one fresh `pi` run per lane, capped at 4
Merge conflicts between parallel agents are the top reported multi-agent failure;
the converged mitigation is mapping file-touch sets before parallelizing, one
git worktree per agent, and a practical ceiling of 2–4 lanes before coordination
overhead dominates ([Intility engineering](https://engineering.intility.com/article/agent-teams-or-how-i-learned-to-stop-worrying-about-merge-conflicts-and-love-git-worktrees),
[MindStudio worktrees](https://www.mindstudio.ai/blog/git-worktrees-parallel-ai-coding-agents)).
**The architect owns the fan-out.** The spec splits the slice into 1–4 lanes
whose file sets are checked for overlap; each lane is an isolated worktree
running its own `pi` process (`cd`'d into the worktree — pi has no working-dir
flag), writing its own lane report (`docs/lanes/`); the architect runs per-lane
boundary checks (`git status` must show only declared files, `git log` must show
no builder commits), commits each passing lane, and merges sequentially with gate
smoke-runs after every merge. Keeping fan-out in the architect rather than any
builder-internal subagent feature makes a merge conflict a detectable spec defect
instead of a silent hazard, and isolates per-lane failure (discard one lane, not
the slice). pi keeps each lane single-agent and the parallelism explicit, which
is exactly what this rule wants.

### R9. Supervise asynchronously; never block on the builder
Fable 5 is specifically tuned for this: "significantly more dependable at
dispatching and sustaining parallel subagents… prefer async communication over
blocking on each return" ([Prompting Fable 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5)).
The dispatch runs `pi -p` in the background; the architect ends its turn or
does other judgment work, then runs the post-flight checks when the run
completes. Multi-hour builder runs are normal — with a cheap metered model their
cost stays small, so run length is bounded by the work, not a quota.

### R10. Grounded progress claims — audit every status against tool output
Fable 5 guidance: instruct the model to audit every status claim against a tool
result from the session before reporting; in Anthropic's testing this "nearly
eliminated fabricated status reports." Applied twice here: the architect's own
reports, and the handoff rules for the builder (raw tables/numbers/SHAs only —
"no interpretation, no 'promising'; verdicts belong to the architect and the
human").

### R11. Ground before judging; scale effort to the task
Carried over from your `/orchestrator` skill, and matching Claude Code best
practices: read the project's own operating docs (CLAUDE.md/AGENTS.md → README →
architecture docs) and learn its verification gate before any judgment; a wrong
assumption multiplies through every dispatch. And not everything needs the loop:
trivial work gets done directly; the full pipeline is for slice-sized work and
up. "Every component in a harness encodes an assumption about what the model
can't do on its own" — don't run a $200 harness on a $9 task
([Harness Design](https://www.anthropic.com/engineering/harness-design-long-running-apps)).

### R12. Keep the skill thin, declarative, and prunable
Two reasons. (a) Claude Code skill mechanics: only descriptions sit in context
until invoked, but the body stays in context for the session — keep it terse,
push detail to referenced files ([Skills docs](https://code.claude.com/docs/en/skills)).
(b) Obsolescence: "skills developed for prior models are often too prescriptive
for Claude Fable 5 and can degrade output quality" (Fable 5 guide), and the
Claude Code team's own position is that scaffolds get obsoleted by better models
([Latent Space, harness engineering](https://www.latent.space/p/harness-eng)).
The skill states *invariants* (the rules above) and *interfaces* (the dispatch
contract), not step-by-step micro-procedures. Review it against each new model
generation and delete what the model now does unprompted.

---

## 4. The builder interface (`pi`)

The exact flags, providers, and model ids are read from the installed CLI
(`pi --help`, `pi --list-models <provider>`, pi's bundled `docs/`); the precise
dispatch commands live in `dispatch.md`. This section records only the
*properties the design leans on* — not a flag list to keep in sync:

- **Non-interactive headless runs** (`pi -p`) that loop plan→act→test and exit,
  with the slice spec handed in as a file (no shell quote-mangling).
- **Reasoning effort is a per-run knob** that maps directly onto the architect's
  `xhigh`/`high` vocabulary — so effort is a spec decision, not a config chore.
- **Tool scoping is the only write control** (there is no sandbox): a builder gets
  write/edit/bash; a reviewer is genuinely inspect-only (`read,grep,find,ls` over a
  diff); a researcher drops write/edit but keeps `bash` (curl to data APIs) and a
  `web_search` tool. That's enough scoping to express the roles.
- **A structured event stream** for liveness monitoring, plus plain-text capture
  for report-style runs.
- **Fresh-by-default sessions** with opt-in resume — exactly the fresh-context-
  per-slice property R7 wants, with same-slice follow-up still available.
- **Repo-resident standing context** (`AGENTS.md`/`CLAUDE.md` loaded by default),
  so repo build/test commands live in the repo and the loop's PHASE rules stay in
  the versioned dispatch block.
- **No built-in sandbox and no review subcommand.** pi's own security doc is
  explicit: *"Real isolation needs to come from the operating system or a
  virtualization/container boundary."* So isolation is worktree+branch per lane,
  a verified "don't commit" prompt rule, and **running the loop inside a
  container** (§6, README); the cross-model gate is a fresh read-only reviewer
  (R3), not a CLI feature.

The model lives in one place — `ARCHITECT_BUILDER_MODEL` (default
`deepseek/deepseek-v4-pro`) plus the matching provider key — so the whole loop
swaps engine with one variable.

Billing note: **per-token on the provider's API key**, not a flat-rate
subscription (cheapness is covered in §1). The real cost of this provider choice
is confidentiality: **your source is sent to a third-party (overseas) model API**
(§6, README security note). For code you cannot send out, point `models.json` at a
self-hosted open-weights model
(vLLM/Ollama) on the same OpenAI-compatible interface — pi treats it identically.

---

## 5. The loop, end to end

```
┌──────────────────────────── one work block ────────────────────────────────┐
│                                                                            │
│  /architect                                                                │
│   0. Ground: CLAUDE.md/AGENTS.md → verification gate → docs/HANDOFF.md     │
│   1. Arbitrate: every open disagreement → ACCEPT/REJECT/MODIFY + why       │
│   2. Judge: run gates yourself; verdict per gate vs verbatim frozen text   │
│      PASS / FAIL / INVALID → kill / continue                               │
│   3. Spec next slice: objective + output format + tool guidance +          │
│      boundaries + out-of-scope; freeze gates to docs/gates/<slice>.md;     │
│      commit the freeze                                                     │
│   4. Dispatch: 1-4 parallel `pi` lanes, one git worktree each             │
│      (background, fresh context, xhigh default). Per lane: PHASE 0         │
│      disagree-or-fail → PHASE 1 contracts frozen → PHASE 2 build own       │
│      files only → raw lane report (docs/lanes/), no commits                │
│   5. Post-flight per lane: raw-only? disagreements raised? gates           │
│      untouched? in-bounds? → architect commits + merges lanes with         │
│      gate smoke-runs; verdict waits for next block                         │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
         repo carries everything across the gap between blocks
```

The human reads the handoff between blocks and overrides anything. Architect
verdicts on a slice always happen in a **later** architect session than the one
that dispatched it — the dispatcher never grades the run it launched in the same
breath (fresh-context judgment, R3).

### Optional pre-spec research fan-out

Between judging and speccing, the architect may run a research phase: 3–5
parallel `pi` researchers (`--tools read,grep,find,ls,bash,web_search` — no
`write`/`edit`; a `web_search` tool plus `curl` for the keyless data APIs), each
answering one narrow non-overlapping question, with the architect adversarially
verifying load-bearing claims and writing `docs/prd/<slice>.md` itself. Design
decisions behind it:

- **Trigger-gated, not always-on.** "Research if you think it helps" either
  fires constantly or never; instead the skill names three concrete triggers
  (slice depends on external APIs/libraries/versions new to the repo; a
  technology choice needs facts nobody has; the human asks) and defaults to
  skip — the builder's verify-against-reality requirement already covers
  routine API checks. (Trigger-gating is about avoiding noise and stale lanes,
  not cost.)
- **Progressive disclosure.** The mechanics live in `research.md`, read only
  when a trigger fires — the default architect context never pays for them
  (R12, per [Skills docs](https://code.claude.com/docs/en/skills) guidance to
  push detail to referenced files).
- **pi researchers, Fable judgment.** Research is coverage work — it runs at
  `high` thinking (xhigh buys nothing for gathering), with a reduced tool set (no
  `write`/`edit`): a `web_search` tool (the `pi-search-hub` package — keyless
  DuckDuckGo, or Tavily with a key) plus `curl` for the keyless data endpoints in
  `lanes.md`/`research.md`.
  Verification of load-bearing claims and PRD authorship stay with the
  architect — researchers are explicitly forbidden from making
  recommendations, the research-side equivalent of "raw results only" (R3).
- **Findings discipline** mirrors deep-research harnesses: every finding
  carries a URL, date, exact quote/figure, and confidence tag; disagreements
  between sources are reported, not resolved; "NOT FOUND" beats inference.
  Multi-angle decomposition (docs / changelogs / failure reports /
  alternatives) follows the multi-modal-sweep pattern from
  [Anthropic's multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system).
- **The PRD is repo memory; raw findings are not.** `docs/prd/<slice>.md` is
  committed with citations (R1); raw researcher output stays in the gitignored
  `.architect/research/`. The builder's PHASE 0 challenges the PRD like any
  other spec input.

### Two skills: `/architect` and `/architect-research`

Discovery-scale research (brainstorming, technology selection, SOTA surveys)
is a **separate skill**, not a mode of the loop. Three reasons: different
invocation pattern (discovery precedes a project; the loop runs per work
block), different deliverable (a decision report vs a dispatch), and cost —
research-grade fan-out runs ~15× chat-level tokens
([Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system)),
so it must be deliberately invoked, never a side-effect. The loop's step 3
routes: discovery scale → `/architect-research`; narrow slice facts → the
inline fan-out above.

`/architect-research` encodes the methodology found across the surveyed
deep-research systems. As of v2.3 the decomposition is **scout-first and
topic-designed, not a fixed lane taxonomy** — a 2026-06 evidence review found
all five production deep-research systems (OpenAI DR, Anthropic, Gemini,
Perplexity, Kimi) use adaptive planner-driven decomposition and none uses
fixed lanes; 4/5 leading OSS frameworks generate the decomposition with an
LLM; and dynamic beats static decomposition on GAIA
([OAgents](https://arxiv.org/abs/2506.15741): 47.88 static → 51.52 dynamic;
[AOrchestra](https://arxiv.org/abs/2602.03786): on-demand subagent
construction +16.28% relative). The six source-class sections in `lanes.md`
became a tactics library the orchestrator draws from when designing lanes:

- **Scout → design → fan out.** For brainstorm-scale questions, one cheap
  pi scout (~10 searches) maps terminology, load-bearing
  systems, named people, and the topic's natural fault lines; the architect
  then designs 3–6 topic-specific lanes from that map. Source-derived
  perspective discovery was STORM's largest measured lever (unique references
  99.83 vs 54.36 without it); Anthropic's lead agent and OpenAI/Gemini's
  user-visible research plans are the production analogs. Comparisons and
  fact-finds skip the scout — recon that tells you nothing is pure latency.
- **Effort scaling embedded in the prompt** — 1 researcher for fact-finds,
  2–4 for comparisons, 4–6 designed lanes for surveys; search budgets 5/15/25
  by tier; ≤5 subjects per researcher (context-exhaustion guard — a
  researcher that fills its window dies without writing output; bisect dead
  lanes); saturation stop (two no-new-fact searches); max 2 gap-fill rounds.
  Scaling numbers from Anthropic's published orchestrator heuristics —
  without them, leads over- or under-delegate.
- **Perspective-diverse decomposition, overlap-checked** before dispatch
  (Stanford [STORM](https://arxiv.org/abs/2402.14207)'s
  perspective-guided questioning; the direct antidote to query collapse).
- **Scope → brief → plan-before-burn** (LangChain
  [Open Deep Research](https://github.com/langchain-ai/open_deep_research)'s
  brief-as-north-star; Gemini's user-visible plan). The brief is restated in
  the report so scope drift is auditable.
- **Verification as a separate pass against raw sources**: ≥2
  independent-origin sources per load-bearing claim; four-state tags
  (VERIFIED/UNVERIFIED/DISPUTED/SUSPICIOUS); adversarial falsification
  searches; **citations only from URLs fetched this session** — even
  search-grounded agents fabricate
  [3–13% of URLs](https://arxiv.org/pdf/2604.03173); recency discipline
  (dated claims, date-restricted queries) because retrieval systematically
  favors stale sources.
- **Parallelize gathering, never synthesis** — one author writes the whole
  report (LangChain's section-parallel writer produced disjoint reports;
  Anthropic's CitationAgent exists to stop summarizing-of-summaries).
  Output is decision-oriented: answer-first, per-finding "what would change
  this conclusion", explicit open questions.
- **Expert opinion as a second-wave lane with its own evidence class.** You
  can't track experts until you know who they are, so lane 6 dispatches in
  the gap round, roster-seeded by the first wave (survey authors, top-repo
  maintainers, recurring names). Platform reality is encoded: experts' blogs
  and HN's keyless Algolia author search are the reliable channels; X is
  login-walled for agents (use `site:x.com` indexed search + profile URLs,
  not third-party viewers), and Bluesky's public search API has returned 403
  since March 2025 ([bsky-docs#332](https://github.com/bluesky-social/bsky-docs/issues/332)).
  Opinions are reported as dated, conflict-of-interest-flagged positions and
  never count toward the ≥2-source rule — but expert *disagreements* are
  first-class findings, since they locate the genuinely open questions.
- **Verified source-class endpoints** live in `lanes.md`: arXiv API recency queries,
  Semantic Scholar citation snowballing (the most reliable "latest papers"
  method), deps.dev/ecosyste.ms dependents (adoption evidence beats stars —
  ~4.5M [fake stars](https://arxiv.org/abs/2412.13459) documented), the
  emerging-vs-hype conjunction gate, the production-grade gate + four-category
  pattern-mining procedure, HN Algolia. Papers With Code is dead (July 2025;
  HF Papers succeeded it) — a stale-source trap the lane file flags.

---

## 6. Failure modes → mechanical mitigations

| Failure mode | Mitigation in this design |
|---|---|
| Reward hacking / gate tampering | Gates committed pre-dispatch in `docs/gates/`; post-flight `git diff` check; tampering = automatic FAIL (R2) |
| Builder grades own work | Raw-results-only handoff; architect runs gates itself; cross-model review (R3, R10) |
| Goalpost moving | Verbatim gate quoting; gates never edited after results; missing gate = spec defect, frozen for next slice only (R2, R4) |
| Scope creep | Explicit out-of-scope list per slice; silent scope additions = builder failure; architect flags creep by name (R5, R6) |
| Context rot | Architect context holds judgment only; fresh builder process per slice; repo is the memory (R1, R7) |
| Merge conflicts between lanes | Disjoint-file-set lanes, ≤3–4, worktrees, one reviewer lane gating merges (R8) |
| Placeholder implementations | Gate commands are end-to-end and executable; "search before implementing; no placeholder code" in the builder block (R4) |
| Broken repo after a long run | One slice per iteration; commit per lane; `git reset` + re-dispatch over rescue prompting (R7) |
| Builder commits / touches `.git` (no sandbox) | Worktree+branch per lane; "don't commit" prompt rule; post-flight `git log <freeze>..` shows no builder commits → lane FAIL; architect owns every merge (R8) |
| Unattended builder with full host access (no sandbox) | Run the whole loop in a container/devcontainer with only the workspace mounted; reduced tool sets for non-builders; metered third-party API → exclude secrets/sensitive repos or self-host the model (§4, README) |
| Fabricated status reports | Every status claim audited against a tool result, both sides (R10) |
| Gate-passing but unmergeable work | Judge reads the diff against spec intent, not gate output alone — METR: 38% test-pass, 0 mergeable as-is; cross-model review for high-stakes (R3, R4) |
| Builder gaming visible gates | Gates frozen + read-only; architect-run verification; no builder iterate-against-gate feedback loops (ImpossibleBench: visible-test loops raised cheating 33%→38%) (R2, R3) |
| Vacuous / self-referential test (green but tests nothing) | Behavioral gate must call the named production symbol; judge reads the test *body*, not just red/green — a test that re-derives its expected value from literals is INVALID (R2, R4) |
| Shared data verified on the wrong copy | Gate asserts the consumer's real code path (not a headless equivalent); spec tells the builder to grep for other definitions of the datum first, so a fix doesn't leave a duplicate broken (R4) |
| Unit-pass but real-medium-broken output | Live-render gate measured the way the medium measures + a live-path exercise of the running app before merge — the gap unit tests / typecheck / a static look all miss (R4) |
| Stalled unattended runs | Liveness checks on the output stream; diagnose child process tree; kill narrowest first; explicit timeouts on every long command (dispatch.md) |
| Hung builder at launch (no output, no CPU) | `dispatch-pi.sh` / `confined-pi.sh` watch output bytes + `/proc` CPU jiffies and auto-kill+re-dispatch with a fresh session id when both stay zero past a threshold (dispatch.md) |
| Researcher context exhaustion | ≤5 subjects per lane; hard context rules in the preamble; bisect-and-redispatch dead lanes (lanes.md) |
| Harness bloat / obsolescence | Thin declarative skill; per-model-generation pruning review (R12) |

---

## 7. What this deliberately is not

- **Not a general-purpose orchestrator.** Your `/orchestrator` skill covers
  single-model plan→delegate→review inside Claude Code. This skill is the
  cross-vendor loop; it imports `/orchestrator`'s grounding, delegation-contract,
  and verify-it-yourself rules rather than duplicating the whole pipeline.
- **Not an autonomous infinite loop.** The human sits between work blocks by
  design — that's where kill/continue authority lives. If you want unattended
  multi-block runs, the dispatch step composes with `claude -p` / scheduled
  jobs, but that's an extension, not the default (and note `claude -p` draws on
  separate Agent SDK credits from June 15, 2026).
- **Not just an autonomous builder.** `pi -p` already loops
  plan→act→test against a stopping condition inside one run. This design adds the
  separation around that loop: cross-vendor judgment, frozen external gates,
  arbitration, and repo-resident memory across runs.

---

## 8. Sources

**Anthropic (official):**
[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) ·
[Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) ·
[Writing Tools for Agents](https://www.anthropic.com/engineering/writing-tools-for-agents) ·
[Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) ·
[Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) ·
[Demystifying Evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) ·
[Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) ·
[Managed Agents](https://www.anthropic.com/engineering/managed-agents) ·
[Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) ·
[Skills](https://code.claude.com/docs/en/skills) ·
[Subagents](https://code.claude.com/docs/en/sub-agents) ·
[Hooks](https://code.claude.com/docs/en/hooks) ·
[Headless mode](https://code.claude.com/docs/en/headless) ·
[Fable 5 announcement](https://www.anthropic.com/news/claude-fable-5-mythos-5) ·
[Prompting Claude Fable 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5)

**pi — builder CLI (authoritative source is the installed CLI, not this doc):**
the live surface is `pi --help` (flags + the provider/env-var list),
`pi --list-models <provider>` (exact model ids), and pi's bundled `docs/`
(`providers.md`, `models.md`, `security.md`, `containerization.md`). Entry point:
[pi.dev](https://pi.dev). This document and `dispatch.md` describe the *pattern*;
they deliberately don't re-tabulate pi's flags or model list — read them from the
CLI so they can't go stale.

**Evidence reviews (2026-06, architect-verified primary sources):**
[Geng & Neubig — async SE agents, worktree+manager topology](https://huggingface.co/papers/2603.21489) ·
[PEAR — weak planners hurt more than weak executors](https://arxiv.org/abs/2510.07505) ·
[AgentForge — execution-grounded role decomposition](https://arxiv.org/abs/2604.13120) ·
[ImpossibleBench — test-exploitation in coding agents](https://arxiv.org/abs/2510.20270) ·
[METR — SWE-bench-passing PRs mostly unmergeable](https://metr.org/blog/2025-08-12-research-update-towards-reconciling-slowdown-with-time-horizons/) ·
[Cross-Context Review — fresh-context judging wins](https://arxiv.org/abs/2603.12123) ·
[Chroma — context rot](https://www.trychroma.com/research/context-rot) ·
[OpenAI — harness engineering / AGENTS.md rot](https://openai.com/index/harness-engineering/) ·
[Cognition — multi-agents: what's actually working](https://cognition.ai/blog/multi-agents-working) ·
[OAgents — static vs dynamic decomposition on GAIA](https://arxiv.org/abs/2506.15741) ·
[AOrchestra — on-demand subagent construction](https://arxiv.org/abs/2602.03786) ·
[OpenAI BrowseComp — aggregation + failure modes](https://openai.com/index/browsecomp/) ·
[DeepResearch Bench leaderboard (RACE/FACT)](https://huggingface.co/spaces/muset-ai/DeepResearch-Bench-Leaderboard/blob/main/data/leaderboard.csv)

**Community / experts:**
[obra/superpowers](https://github.com/obra/superpowers) ·
[Ralph Wiggum loop](https://ghuntley.com/ralph/) ·
[A Brief History of Ralph](https://www.humanlayer.dev/blog/brief-history-of-ralph) ·
[Advanced Context Engineering (HumanLayer)](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents) ·
[Simon Willison — Agentic Engineering Patterns](https://simonwillison.net/guides/agentic-engineering-patterns/how-coding-agents-work/) ·
[Simon Willison on Fable 5](https://simonwillison.net/2026/Jun/9/claude-fable-5/) ·
[Latent Space — Harness Engineering](https://www.latent.space/p/harness-eng) ·
[GitHub Spec Kit](https://github.com/github/spec-kit) ·
[Steve Yegge — Beads](https://steve-yegge.medium.com/introducing-beads-a-coding-agent-memory-system-637d7d92514a) ·
[Reward hacking in self-improvement](https://openreview.net/forum?id=ikrQWGgxYg) ·
[Obfuscated reward hacking](https://arxiv.org/pdf/2503.11926) ·
[Worktrees for parallel agents](https://engineering.intility.com/article/agent-teams-or-how-i-learned-to-stop-worrying-about-merge-conflicts-and-love-git-worktrees)

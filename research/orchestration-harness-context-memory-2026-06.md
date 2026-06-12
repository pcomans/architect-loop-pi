# Research: orchestration, harness, context & memory practices for the Architect Loop

Date: 2026-06-12. Method: 9 parallel GPT-5.5 web researchers (xhigh, read-only,
live search) across academic / popular-repos / cutting-edge / production /
general-web / expert-opinion / supervision lanes; load-bearing claims verified
by the architect against primary sources. Raw findings: `.architect/research/`
(local). Citations are URLs fetched this session, tier-labeled and dated.

## The brief

What do mid-2026 best practices in (1) multi-agent orchestration, (2) harness
engineering, (3) context engineering, (4) agent memory/state imply for the
next revision of `/architect` — one judgment-only Claude Fable architect
(all design, specs, gates, arbitration, final review) dispatching 1–4
parallel headless GPT-5.5 builders in isolated git worktrees, repo as the
only memory — to maximize the judgment model's leverage while offloading all
engineering?

## BLUF

The loop's architecture is independently validated from three directions:
academia (manager agent + git-worktree-isolated engineers measured at +26.7%
PaperBench / +14.3% Commit0 over single-agent — Geng & Neubig, CMU), vendor
practice (Cognition's 2026 "map-reduce-and-manage, single-threaded writes,
clean-context reviewer"), and controlled study (cross-context review beats
same-session review; "the benefit comes from context separation itself").
The strongest evidence says invest MORE in the architect — weak planners
hurt more than weak executors — and the loop's four needed refinements are:
(1) judge the diff, not just the gates (passing tests ≠ mergeable);
(2) keep the handoff a short table-of-contents or it rots;
(3) treat integration/review as the scaling bottleneck, not build capacity;
(4) supervision needs explicit timeouts + narrowest-kill watchdogs — every
platform has unsolved stall problems.

## Verified load-bearing findings (each: claim → implication)

1. **Planner quality is load-bearing.** [VERIFIED, primary] PEAR (arXiv
   2510.07505, Oct 2025): "weak planner degrades overall clean task
   performance more severely than a weak executor." AgentForge (arXiv
   2604.13120, Apr 2026): 40.0% SWE-bench Lite vs 14.0% single-agent;
   removing the planner drops 42.0%→19.0%.
   → Implication: max effort on architect design/specs is the right spend;
   never economize the spec to save architect tokens. Would change if: a
   study showed spec quality saturates for strong builders.

2. **Worktree isolation + centralized delegation is the measured-best
   topology for shared-artifact SWE.** [VERIFIED, primary] Geng & Neubig
   (Mar 2026): manager agent, engineer-per-git-worktree, async event loop:
   +26.7% PaperBench, +14.3% Commit0. Cursor (Jan 2026): naive shared-file
   locking collapsed 20 agents to the throughput of 2–3. Forced-diverse
   parallel planning shows no clear gain over repeated planning (M1-Parallel).
   → Implication: keep architect-orchestrated disjoint lanes; don't add
   swarm/debate topologies; don't fan out for diversity's sake.

3. **Cognition reversed: the 2025 anti-multi-agent position became
   "map-reduce-and-manage" in Apr 2026.** [VERIFIED, primary] Single-threaded
   writes; reviewer with "completely clean context"; "smart friend" —
   delegate hard decisions to a stronger model. Devin-manages-Devins ships
   with isolated VMs + a conflict-resolving coordinator.
   → Implication: the loop's differentiator (judgment-only architect,
   builders never integrate) is now the documented industry direction; keep
   writes (merges) exclusively architect-side.

4. **Gates are necessary, gameable, and insufficient.** [VERIFIED, primary]
   AgentForge: mandatory sandboxed execution drives its gains. ImpossibleBench
   (arXiv 2510.20270): agents delete failing tests / overload operators;
   iterating against visible tests raised cheating 33%→38%; LLM monitors
   caught only 42–65% on SWE-bench-style tasks. METR (Aug 2025): 38%±19%
   test success but ZERO of the manually reviewed agent PRs were mergeable
   as-is (avg 42 min human fix).
   → Implication: frozen read-only gates stay; add "judge the diff, not just
   the gate output" to the Judge step; keep cross-model review for
   high-stakes slices; never let gate-pass alone produce a CONTINUE verdict.

5. **Fresh-context judging is measurably better.** [VERIFIED, primary]
   Cross-Context Review (arXiv 2603.12123, Mar 2026): F1 28.6% vs 24.6%
   same-session self-review (p=0.008); repeated same-session review is
   WORSE (21.7%). → Implication: the "never judge in the session that
   dispatched" rule is evidence-backed; do not soften it for convenience.

6. **Repo memory files work but rot; short map > big manual.** [VERIFIED,
   ≥2 independent] OpenAI harness engineering (Feb 2026, Ryan Lopopolo):
   monolithic AGENTS.md "rots instantly"; keep ~100 lines as a table of
   contents with repo docs as system of record; their agent-first repo hit
   ~1M LoC / ~1,500 PRs with 3 engineers. Anthropic context engineering
   (Sep 2025): subagent summaries of 1,000–2,000 tokens; isolate deep work
   in subagent contexts. No measured evidence anywhere that vector/graph
   memory services beat plain repo/file memory for single-project coding
   agents (two lanes independently: NOT FOUND).
   → Implication: repo-as-memory is the right substrate; add handoff-pruning
   discipline (TL;DR + pointers, archive old slices); keep lane reports
   compact. Would change if: a measured file-vs-service comparison appears.

7. **Integration/review is the scaling bottleneck.** [VERIFIED, primary +
   med] Willison (Oct 2025): "I can only focus on reviewing and landing one
   significant change at a time." 27.67% merge-conflict rate measured across
   142K agentic PRs (arXiv 2604.03551). → Implication: the 1–4 lane cap is
   right; scale architect review capacity (cross-model review, structured
   lane reports), not lane count.

8. **Supervision is unsolved platform-wide; the working pattern is
   diagnose-then-narrowest-kill with explicit timeouts.** [VERIFIED, mixed]
   Codex subagent default per-worker timeout 1800s; Claude Code stall knob
   CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS=600000; practitioner watchdog
   (checkloop) checks live descendants + CPU before killing because naive
   idle-kill destroyed valid work; stall reports exist for Codex (300s idle
   disconnects), Cursor (90–100% tool-timeout reports), Claude Code (Windows
   bash hangs). → Implication: the stall-detection + narrowest-kill rule
   added to dispatch.md (2026-06-12) matches best known practice; explicit
   per-command timeouts in the builder block are mandatory, not optional.

9. **Cross-model pairing helps conditionally, not universally.** [VERIFIED,
   primary] Aider: R1+Sonnet 64.0% beat solo R1, but "o1 paired with Sonnet
   didn't produce better results than just using o1 alone." No controlled
   cross-vendor-vs-same-model review study exists (NOT FOUND, two lanes).
   → Implication: justify the cross-vendor split by trust separation
   (no same-model sycophancy/self-preference — arXiv 2504.03846) and quota
   economics, not by assumed quality gains.

## Expert positions map (opinions, not facts; COI flagged)

- **Pro scoped parallel subagents**: Willison (independent, Mar 2026 —
  value is preserving root context; "tempting to go overboard"), Anthropic
  (vendor — orchestrator-workers when subtasks unknown), OpenAI (vendor —
  "Humans steer. Agents execute."), Jesse Vincent (Superpowers author —
  "Specs are the thing that matters now").
- **Conditionally pro, formerly anti**: Cognition/Walden Yan (vendor) —
  2025 "wrong way"; 2026 "some setups work… writes stay single-threaded."
- **Standing warnings**: METR/David Rein — test-passing ≠ mergeable;
  Chroma (Hong/Troynikov/Huber) — more context is not better, 18 models
  degrade with length.
- **Genuine disagreement worth tracking**: whether agent-to-agent review
  (OpenAI practice) suffices vs human/architect-read-the-diff (METR's data
  says no, for now).

## Open questions (with the experiment that would resolve each)

1. Architect+isolated-builders vs swarm/debate, controlled: NOT FOUND —
   would need a benchmark run of this exact loop vs AgentForge-style roles.
2. Cross-vendor vs same-model review quality: NOT FOUND — A/B the judge
   model on identical slices (BenchPair is literally built for this).
3. File/repo memory vs vector/graph services for single-project agents:
   NOT FOUND — measured comparison absent across two lanes.
4. A reproducible lane-count payoff curve: NOT FOUND — anecdotes only.

## Changes applied to the skill from this research (2026-06-12)

1. Judge step: gate-pass is necessary, not sufficient — read the diff
   against spec intent (METR, ImpossibleBench).
2. Handoff hygiene: keep HANDOFF.md a short table-of-contents; archive old
   slices; lane reports stay compact (OpenAI rot finding, Anthropic
   1–2k-token summaries).
3. Lane report status line: COMPLETE / COMPLETE_WITH_CONCERNS / BLOCKED
   (orchestrator-skill parity; cheap post-flight signal).
4. Researcher lanes (architect-research): hard context-budget rules in the
   preamble; ≤5 subjects per researcher — two of nine researchers died of
   context exhaustion before writing findings; bisect lanes on death.
5. (Already landed earlier today, now evidence-backed): stall detection,
   narrowest-kill, explicit timeouts in the builder block.

# Research fan-out reference

Read this only when a research trigger fires (see SKILL.md step 3). The fan-out
uses `pi` as parallel web-research subagents — no `write`/`edit`, with a
`web_search` tool and `bash` for curling data APIs — and the architect keeps all
judgment: it verifies the load-bearing claims and writes the PRD itself.

## Fan out

Decompose the question into 3–5 narrow, NON-OVERLAPPING research questions.
Cover different angles, not the same angle five times — typical split:
official docs/reference, changelog/breaking changes, community failure reports,
alternatives/comparisons, security/operational constraints.

One fresh `pi` run per question, all launched in parallel, in the background.
Researchers get an inspect-only tool set plus `bash` (for `curl`), never
`write`/`edit`, and their report is the stdout the architect captures:

```bash
( cd <repo-root> && \
  pi -p --mode text \
    --model "${ARCHITECT_RESEARCH_MODEL:-deepseek/deepseek-v4-flash}" --thinking high \
    --tools read,grep,find,ls,bash,web_search \
    @.architect/research/<NN>-<topic>.prompt.md \
    > .architect/research/<NN>-<topic>.md ) &
```

Write each research block to a `.prompt.md` file and pass it as `@<file>` — never
as a shell argument; `@file` avoids the quote-mangling that breaks big prompts.

- `--tools read,grep,find,ls,bash,web_search`: no `write`/`edit`, so researchers
  don't modify the repo; the report comes back on stdout. `bash` is for `curl` to
  the keyless data APIs, `web_search` is the general-search tool.
- **Web search**: the `web_search` tool comes from the bundled extension
  (`extensions/web-search/`, installed by `install.sh`) — Tavily if
  `TAVILY_API_KEY` is set, else keyless DuckDuckGo. For source-class endpoints
  (arXiv, Semantic Scholar, OpenAlex, HN Algolia) researchers `curl` directly;
  those need no search engine. The endpoint library is in
  `../architect-research/lanes.md`.
- Effort `high`, not `xhigh` — research is coverage work; xhigh buys nothing
  here (capability, not cost). Synthesis is the architect's.
- Scope each researcher to ≤5 subjects and put hard context rules in the
  block (snippet over page; quote ≤2 sentences; stop the moment you can
  answer) — a researcher that fills its context window dies without emitting its
  report. Bisect and re-dispatch dead lanes; don't re-run as-is.
- Launch ONE canary researcher and confirm it starts cleanly and can reach the
  search API before fanning out.

## Research block template

```
You are a web research agent. Answer ONE question. Do not write code, do not
make recommendations — judgment belongs to the architect who reads your output.

QUESTION: <one narrow question>

OUTPUT FORMAT — a markdown report:
- Findings as bullets. EVERY finding carries: source URL, source date (if
  shown), the exact figure or a short direct quote, and a confidence tag
  (high = primary source / med = reputable secondary / low = single blog or
  forum post).
- Prefer primary sources (official docs, changelogs, release notes, source
  code) over blog posts. Record exact version numbers and dates.
- When sources disagree, report the disagreement — do not resolve it.
- If you cannot find evidence for something, write NOT FOUND — never infer or
  fill gaps from prior knowledge without flagging it as such.
- End with: the 2-3 findings most likely to change an implementation decision.
```

## Gather (architect — this is your work, not another agent's)

1. Read every findings file in `.architect/research/`.
2. Identify the **load-bearing claims** — facts the spec will depend on
   (an API shape, a version constraint, a limit, a deprecation). Adversarially
   verify each: cross-check against a second independent source or the live
   dependency itself. Discard single-source low-confidence claims or mark them
   as open questions.
3. Write `docs/prd/<slice>.md`: problem, decision + why, requirements,
   non-goals, verified facts **with citations**, open questions for the human.
   You write it — researchers gather, the architect judges and decides.
4. Commit the PRD. Raw findings stay in `.architect/research/` (gitignored) —
   only the distilled, cited PRD is repo memory.
5. The slice spec references the PRD instead of restating it; the builder's
   PHASE 0 is expected to challenge the PRD's claims like anything else.

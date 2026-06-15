# AGENTS.md — architect-loop-pi

This file is for agents and contributors working on the **harness itself**
(this repo). For instructions on using the harness to build something, see
the skills in `skills/architect/` and `skills/architect-research/`.

## Repo layout

```
skills/architect/          # /architect skill — the build loop
skills/architect-research/ # /architect-research skill — the research loop
tests/validate_skills.py   # repo sanity checks
install.sh / install.ps1   # skill + pi-search-hub installer
.devcontainer.json         # devcontainer for DevPod / VS Code
```

## Running the validator

```bash
python tests/validate_skills.py   # exit 0 = pass
```

Checks: SKILL.md frontmatter length, required sibling files, .sh scripts
present and executable, fence balance, local links.

## Harness learnings

When you run the architect loop on a real project, you will encounter
issues and make observations specific to the **harness** (pi, dispatch,
stall recovery, worktree isolation, gate design, environment) that are
not specific to the project you're building.

**Capture these as you go:**

1. Copy `skills/architect/templates/HARNESS-LEARNINGS.template.md` to `docs/HARNESS-LEARNINGS.md`
   in your target repo at the start of your first session.
2. Log every harness-level issue as it happens — follow the template format.
3. At the end of the run, open a PR against this repo with your completed
   `HARNESS-LEARNINGS.md` (rename it to reflect your project, e.g.
   `docs/learnings/my-project.md`). Entries that are new and survive review
   will be distilled into the skills so every future run benefits.

**The no-jargon rule (enforced in the template, repeated here because it
matters):** every entry in your learnings log must be understandable by
someone who has never seen your project. Do not name your domain entities,
your file paths, or your stack-specific concepts. Describe the *class of
problem*. If you write "the Cultist builder hung", rewrite it as "a
dispatched builder hung silently with zero output and zero CPU". The
learnings file is consumed by future architects on completely different
projects — project-specific jargon makes an entry useless to them.

## What's already known

The following harness issues were discovered in the first real run and have
already been distilled into the skills:

- **Dispatch launch stalls (~50% of fresh dispatches):** a fresh `pi`
  dispatch can draw a model connection that never streams. Fix: watch
  output bytes + `/proc` CPU jiffies; kill + re-dispatch with a new session
  id. Automated in `skills/architect/scripts/dispatch-pi.sh`.

- **`cd worktree && pi` is not isolation for parallel lanes:** if the
  builder block carries absolute paths, the builder anchors to the canonical
  repo root and writes outside its worktree, corrupting the main checkout.
  Fix: Linux user+mount namespace bind-mount. Automated in
  `skills/architect/scripts/confined-pi.sh`.

- **Vacuous tests pass gates but prove nothing:** a test that re-derives
  its expected value from literals without calling production code is green
  and useless. Fix: read the test body, not just red/green; gate wording
  must name the production symbol under test. Documented in SKILL.md.

- **`TOOLS=` actually enforces read-only; instruction alone does not:** a
  "read-only" reviewer without `--tools read,grep,find,ls` still has
  write/edit/bash. Documented in dispatch.md.

- **Cheap builder model as first-pass judge:** in blind A/B trials, the
  builder model matched or beat the architect's tmux judgment on explicit
  gate checks. Cost win: route first-pass UI/playtest eyeballs to the
  builder model; keep the architect as spot-check backstop. Documented in
  SKILL.md and dispatch.md.

Do not re-log these in your learnings file — they're already in the skills.
Log only things you discover that are NOT covered above.

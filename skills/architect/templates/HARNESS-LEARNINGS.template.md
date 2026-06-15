# Harness learnings log — [your project name]

> **Copy this file to `docs/HARNESS-LEARNINGS.md` at the start of your first
> run.** The architect maintains it across sessions. Contribute back by opening
> a PR against [pcomans/architect-loop-pi](https://github.com/pcomans/architect-loop-pi)
> with your completed log — entries that survive to a PR are distilled into the
> skills so every future run benefits.

---

## ⚠️ Critical rule before writing any entry

**Write as if the reader has never seen your project.** The consumer of this
file is a future architect running a completely different project. They will
not know your domain, your stack, your enemy names, your card names, your
entity types, or your file layout. Every entry must be self-contained and
jargon-free:

- ✅ "A fresh dispatch can draw a model connection that never streams — zero
  output bytes, zero CPU jiffies — and hang silently."
- ❌ "The Cultist builder hung when dispatching the Act 2 enemy lane."

If you catch yourself writing a domain word (a product name, a file path
specific to your repo, a concept that only makes sense in your context),
rewrite the entry to describe the *class of problem* instead.

**What counts as a harness issue:** anything about `pi`, dispatch, the
architect loop, environment setup, tooling, or the interplay between them.
Bugs in the thing you're building are NOT harness issues and do not belong
here.

---

## Status legend

✅ fixed · ⚠️ worked-around · ❓ open · 📝 observation

---

## ENV — environment and tooling issues

> Problems with the container, package installation, CLI flags, or the
> execution environment itself.

<!--
## ENV-1 ✅ [short title]
- **Symptom:** what you observed
- **Root cause:** why it happened
- **Fix:** what resolved it
-->

## OBS — loop-process observations

> Things learned about how the architect loop behaves: dispatch patterns,
> builder behavior, judgment discipline, worktree isolation, stall recovery,
> gate design, post-flight checks.

<!--
## OBS-1 📝 [short title]
- **Where:** which phase / step / script
- **What happened:** describe generically — no project jargon
- **Why it matters:** the class of problem this represents
- **Fix or lesson going forward:** what the harness should do differently
-->

## REF — external data and research issues

> Problems fetching external data during research phases: rate limits,
> redirect chains, broken endpoints, format surprises.

<!--
## REF-1 ⚠️ [short title]
- **Where:** which phase / what kind of data
- **Symptom:** what failed
- **Workaround:** what worked instead
-->

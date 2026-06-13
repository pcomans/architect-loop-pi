# web-search — a `web_search` tool for pi

pi has no built-in web search. This extension registers a `web_search` tool so
the Architect Loop's researchers can search the web with an agent-optimized
backend instead of scraping. Researchers still keep `bash`/`curl` for the keyless
data APIs (arXiv, Semantic Scholar, OpenAlex, HN Algolia) — this just adds clean
general search.

## Backend (hybrid, swappable via env var)

| Condition | Backend | Notes |
|---|---|---|
| `TAVILY_API_KEY` set | [Tavily](https://tavily.com) (`@tavily/core`) | Built for LLM agents; ranked, clean results. Free tier. **Recommended.** |
| otherwise | DuckDuckGo (`duck-duck-scrape`) | Keyless, zero setup. Rate-limited / can be blocked from datacenter IPs. |

Any other search API drops in by editing `index.ts` (Exa, Brave, Jina, a
self-hosted SearXNG) — it's one function.

## Install

`install.sh` / `install.ps1` copy this directory to
`~/.pi/agent/extensions/web-search/` and run `npm install`, so pi auto-discovers
it (`~/.pi/agent/extensions/*/index.ts`) for every session — no flags needed.

Manual:

```bash
cp -r extensions/web-search ~/.pi/agent/extensions/web-search
cd ~/.pi/agent/extensions/web-search && npm install
# optional, for the better backend:
export TAVILY_API_KEY=tvly-...
```

Per-run alternative (no global install): `pi --extension <path>/index.ts ...`.

## Use

The tool exposes `web_search(query, max_results?)`. Researchers enable it via the
tool allowlist, e.g. `pi --tools read,grep,find,ls,bash,web_search -p @lane.md`.
It returns ranked `title / url / snippet` lines — fetch the URL to quote the
primary source; the snippet only locates it.

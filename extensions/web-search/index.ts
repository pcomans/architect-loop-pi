/**
 * web-search — a pi extension that registers a `web_search` tool.
 *
 * Why this exists: pi has no built-in web search, and the Architect Loop's
 * researchers need one. A real `web_search` tool gives cleaner, agent-optimized
 * results than scraping via curl — though researchers keep `bash`/curl too, for
 * the keyless data APIs (arXiv, Semantic Scholar, OpenAlex, HN Algolia).
 *
 * Backend: Tavily (@tavily/core) if TAVILY_API_KEY is set, else keyless
 * DuckDuckGo (duck-duck-scrape).
 *
 * Install: copy this directory to ~/.pi/agent/extensions/web-search/ (install.sh
 * does this) so pi auto-discovers it (~/.pi/agent/extensions/*\/index.ts), or pass
 * `--extension <path>/index.ts` per run. Run `npm install` in the dir either way.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

interface Hit {
	title: string;
	url: string;
	snippet: string;
}

async function searchTavily(query: string, maxResults: number): Promise<Hit[]> {
	// Lazy import so the dependency is only loaded when actually used.
	const { tavily } = await import("@tavily/core");
	const client = tavily({ apiKey: process.env.TAVILY_API_KEY as string });
	const res = await client.search(query, { maxResults });
	return (res.results ?? []).map((r: { title?: string; url: string; content?: string }) => ({
		title: r.title ?? r.url,
		url: r.url,
		snippet: (r.content ?? "").trim(),
	}));
}

async function searchDuckDuckGo(query: string, maxResults: number): Promise<Hit[]> {
	const { search, SafeSearchType } = await import("duck-duck-scrape");
	const res = await search(query, { safeSearch: SafeSearchType.MODERATE });
	return (res.results ?? [])
		.slice(0, maxResults)
		.map((r: { title: string; url: string; description: string }) => ({
			title: r.title,
			url: r.url,
			snippet: (r.description ?? "").replace(/<[^>]+>/g, "").trim(),
		}));
}

function render(query: string, backend: string, hits: Hit[]): string {
	if (hits.length === 0) return `No results for "${query}" (backend: ${backend}).`;
	const lines = hits.map((h, i) => `${i + 1}. ${h.title}\n   ${h.url}\n   ${h.snippet}`);
	return `Search results for "${query}" (backend: ${backend}):\n\n${lines.join("\n\n")}`;
}

export default function webSearchExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "web_search",
		label: "Web search",
		description:
			"Search the web and return ranked results (title, URL, snippet). Use the URLs " +
			"to fetch and quote primary sources; the snippet only locates the source.",
		parameters: Type.Object({
			query: Type.String({ description: "The search query." }),
			max_results: Type.Optional(
				Type.Number({ description: "Max results to return (default 5).", default: 5 }),
			),
		}),
		async execute(_toolCallId, params) {
			const { query, max_results } = params as { query: string; max_results?: number };
			const backend = process.env.TAVILY_API_KEY ? "tavily" : "duckduckgo";
			const hits =
				backend === "tavily"
					? await searchTavily(query, max_results ?? 5)
					: await searchDuckDuckGo(query, max_results ?? 5);
			return { content: [{ type: "text", text: render(query, backend, hits) }], details: { backend, count: hits.length } };
		},
	});
}

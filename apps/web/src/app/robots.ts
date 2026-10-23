import type { MetadataRoute } from "next";

import { siteOrigin } from "@/lib/site-url";

const DISALLOW = ["/api/", "/socket/", "/dev/", "/platform/"];

// AI answer engines named explicitly (search, user-triggered fetches and
// training), so Palee can be read and cited in ChatGPT, Claude, Perplexity,
// Gemini and Apple Intelligence answers. Drop the training agents here to opt
// out of model training without leaving AI search.
const AI_AGENTS = [
  "OAI-SearchBot",
  "ChatGPT-User",
  "GPTBot",
  "Claude-SearchBot",
  "Claude-User",
  "ClaudeBot",
  "PerplexityBot",
  "Perplexity-User",
  "Google-Extended",
  "Applebot-Extended",
];

export default async function robots(): Promise<MetadataRoute.Robots> {
  const origin = await siteOrigin();
  return {
    rules: [
      { userAgent: "*", allow: "/", disallow: DISALLOW },
      { userAgent: AI_AGENTS, allow: ["/", "/llms.txt"], disallow: DISALLOW },
    ],
    sitemap: new URL("/sitemap.xml", origin).toString(),
    host: origin.host,
  };
}

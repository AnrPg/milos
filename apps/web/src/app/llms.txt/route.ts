import { DEFAULT_LOCALE } from "@/i18n/locales";
import { loadSiteFacts } from "@/lib/seo/site-facts";
import { llmsText } from "@/lib/seo/site-info";

// https://llmstxt.org: a plain Markdown summary for AI answer engines.
export async function GET() {
  const { facts, faq } = await loadSiteFacts(DEFAULT_LOCALE);
  return new Response(llmsText(facts, faq), {
    headers: {
      "Content-Type": "text/markdown; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
  });
}

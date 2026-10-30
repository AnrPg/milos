import type { Provider } from "@/api/providers";
import type { BoxConversationSummary } from "@/api/trials";

export type BoxToWrite = { slug: string; name: string };

/**
 * ADR-282: the boxes you belong to that you have not written to yet, so
 * Μηνύματα › Box offers «Γράψε στο …» instead of an empty list. Independent
 * coaches are reached in «Coach».
 */
export function boxesToWrite(providers: readonly Provider[], conversations: readonly BoxConversationSummary[]): BoxToWrite[] {
  const talking = new Set(conversations.map((row) => row.box.organization_id));
  return providers
    .filter((provider) => provider.kind === "gym" && provider.slug && !talking.has(provider.organization_id))
    .map((provider) => ({ slug: provider.slug!, name: provider.name }));
}

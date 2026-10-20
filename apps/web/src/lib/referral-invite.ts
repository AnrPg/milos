import { cache } from "react";

import type { ReferralInvitePage } from "@/api/referrals";
import { apiOriginForProxy } from "@/lib/organization-slug-alias";

/**
 * Server-side read of an invite (ADR-156) for `/r/[code]`, its metadata and
 * its link preview. Null when the code is unknown, revoked, or its member or
 * box is gone. Memoised per request so the page and its metadata share one fetch.
 */
export const loadReferralInvite = cache(async (code: string): Promise<ReferralInvitePage | null> => {
  const response = await fetch(`${apiOriginForProxy()}/api/public/referrals/${encodeURIComponent(code)}`, {
    headers: { accept: "application/json" },
    next: { revalidate: 60 },
  });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`referral invite ${code}: ${response.status}`);
  const data = (await response.json()) as { invite: ReferralInvitePage };
  return data.invite;
});

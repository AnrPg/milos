import { claimReferral, type ReferralClaimResult } from "@/api/referrals";
import { claimBody, claimSettled, codeKey, forgetReferral, readPendingReferrals } from "@/lib/referral-claim";

/** Per kept code: the server's answer, or `"failed"` when it couldn't be claimed. */
export type ClaimResults = Map<string, ReferralClaimResult | "failed">;

let queue: Promise<unknown> = Promise.resolve();
const settled: ClaimResults = new Map();

/**
 * Claims the invites kept on this device, in the order they were last used
 * (ADR-156), so the link used last owns the invite. Calls from
 * the invite page, event links and the app-wide bridge run one after the
 * other, so an invite kept a moment ago is never skipped by a run already
 * under way; a settled answer forgets an invite, a network or server failure
 * keeps it for the next visit. Results (of this page load) are keyed by `codeKey`.
 */
export function claimPendingReferrals(token: string): Promise<ClaimResults> {
  const run = queue.then(async () => {
    for (const entry of readPendingReferrals()) {
      try {
        settled.set(codeKey(entry.code), await claimReferral(token, claimBody(entry)));
        forgetReferral(entry.code);
      } catch (error) {
        if (claimSettled(error)) forgetReferral(entry.code);
        settled.set(codeKey(entry.code), "failed");
      }
    }
    return new Map(settled);
  });
  queue = run.catch(() => undefined);
  return run;
}

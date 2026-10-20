"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";

import { REFERRALS_KEY, type ReferralChannel } from "@/api/referrals";
import { useSession } from "@/components/session-provider";
import { rememberReferral } from "@/lib/referral-claim";

import { claimPendingReferrals } from "./claim";

/**
 * An event link a member shared from «Φέρε φίλο» carries their code
 * (`?ref=`, ADR-156): the friend who opens it is credited to them, through
 * the event (or the member's guest pass).
 */
export function useEventReferral(code: string | null, eventId: string, channel: Extract<ReferralChannel, "event" | "guest_pass">) {
  const { status, tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!code) return;
    rememberReferral({ code, channel, event_id: eventId });
    if (status !== "authenticated" || !token) return;
    void claimPendingReferrals(token).then((results) => {
      if (results.size > 0) void queryClient.invalidateQueries({ queryKey: REFERRALS_KEY });
    });
  }, [channel, code, eventId, queryClient, status, token]);
}

"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";

import { REFERRALS_KEY } from "@/api/referrals";
import { useSession } from "@/components/session-provider";

import { claimPendingReferrals } from "./claim";

/**
 * Once someone is signed in, the invites they opened earlier on this device
 * are credited to the members who sent them (ADR-156), wherever they signed in.
 */
export function ReferralClaimBridge() {
  const { status, tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();

  useEffect(() => {
    if (status !== "authenticated" || !token) return;
    void claimPendingReferrals(token).then((results) => {
      if (results.size > 0) void queryClient.invalidateQueries({ queryKey: REFERRALS_KEY });
    });
  }, [queryClient, status, token]);

  return null;
}

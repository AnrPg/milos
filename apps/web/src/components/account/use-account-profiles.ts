"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchAccountProfiles, switchAccountProfile } from "@/api/account-profiles";
import { useSession } from "@/components/session-provider";

export const ACCOUNT_PROFILES_QUERY_KEY = ["account", "profiles"] as const;

/** The login's profiles; `enabled` lets the account menu skip it for one-profile logins. */
export function useAccountProfiles(enabled = true) {
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  return useQuery({
    queryKey: [...ACCOUNT_PROFILES_QUERY_KEY, currentUser?.id ?? null],
    queryFn: () => fetchAccountProfiles(token!),
    enabled: enabled && Boolean(token),
    staleTime: 60 * 1000,
  });
}

/**
 * Opens a session for another profile of the same login, then reloads on
 * Home so nothing cached for the previous profile survives.
 */
export function useSwitchProfile() {
  const { tokens, switchSession } = useSession();
  const [switchingTo, setSwitchingTo] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  async function switchTo(userId: string) {
    if (!tokens || switchingTo) return;
    setFailed(false);
    setSwitchingTo(userId);
    try {
      const issued = await switchAccountProfile(tokens.access_token, userId);
      await switchSession(issued);
      // A full load on purpose: every cache of the previous profile goes.
      // eslint-disable-next-line @next/next/no-location-assign-relative-destination
      window.location.assign("/");
    } catch {
      setFailed(true);
      setSwitchingTo(null);
    }
  }

  return { switchTo, switchingTo, failed };
}

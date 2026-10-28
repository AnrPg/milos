"use client";

import { useQuery } from "@tanstack/react-query";

import { PASSWORD_RESETS_KEY, fetchPasswordResets } from "@/api/password-resets";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { FRESHNESS } from "@/lib/query-policy";
import { hasStaffRole } from "@/lib/role-navigation";

/**
 * The resets inbox of a person who handles them (the vendor, staff, coaches),
 * shared by the account menu and Εγώ. A new request reaches the handlers as a
 * notification, and that event refreshes it (TopNav), so it is not polled.
 */
export function usePasswordResetsInbox() {
  const { currentUser, tokens } = useSession();
  const { memberships } = useSelectedMembershipRole();
  const handles = Boolean(currentUser?.vendor) || memberships.some((entry) => hasStaffRole(entry));
  return useQuery({
    queryKey: PASSWORD_RESETS_KEY,
    enabled: Boolean(tokens?.access_token) && handles,
    queryFn: () => fetchPasswordResets(tokens!.access_token),
    staleTime: FRESHNESS.pushed,
  });
}

/**
 * ADR-187: the password resets staff and vendors handle. Their way in lives
 * in Εγώ › Βοήθεια & ξενάγηση (ADR-196); the count of resets waiting on
 * someone shows on that row too, so none goes unseen.
 */
export function usePasswordResets() {
  const { currentUser } = useSession();
  const resets = usePasswordResetsInbox();
  const requests = resets.data?.requests ?? [];
  return {
    shown: requests.length > 0 || Boolean(currentUser?.vendor),
    toAct: requests.filter((request) => ["open", "mine", "expired"].includes(request.state)).length,
  };
}

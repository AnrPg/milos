"use client";

import { useRouter } from "next/navigation";

import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref } from "@/lib/organization-slug";
import { hasStaffRole } from "@/lib/role-navigation";
import { setView } from "@/lib/view-mode";

/**
 * Εγώ › Διαχείριση (ADR-103 amended, ADR-196 amended 2026-10-24): the way
 * back from the social app to the console for anyone with a staff role.
 * Opens the selected provider's console, or the first one where the person
 * is staff, and remembers the console view on this device. `null` when the
 * person is staff nowhere.
 */
export function useOpenConsole(): (() => void) | null {
  const router = useRouter();
  const { membership, memberships } = useSelectedMembershipRole();
  const target = hasStaffRole(membership) ? membership : memberships.find((entry) => hasStaffRole(entry));
  if (!target) return null;
  return () => {
    setView("staff");
    router.push(adminHref("/admin", target.organization.slug ?? null));
  };
}

import type { ClassPlacementClass } from "@/api/admin-users";

/**
 * ADR-225: why a class cannot take the member, in staff words. The codes are
 * the booking error codes the API answers, so the same text explains a
 * disabled class in the list and a refused placement.
 */
const REASON_KEYS: Record<string, string> = {
  slot_full: "placementReasonFull",
  class_paused: "placementReasonPaused",
  class_cancelled: "placementReasonCancelled",
  class_not_published: "placementReasonDraft",
  slot_in_past: "placementReasonPast",
  already_booked: "placementReasonWaitlisted",
  finance_allowance_exhausted: "placementReasonNoVisits",
  finance_class_type_not_included: "placementReasonClassType",
  finance_location_not_included: "placementReasonBranch",
  finance_time_window_not_included: "placementReasonHours",
  finance_membership_frozen: "placementReasonFrozen",
  location_out_of_scope: "placementReasonOtherBranch",
};

export function placementReasonKey(code: string | null | undefined): string | null {
  if (!code) return null;
  if (REASON_KEYS[code]) return REASON_KEYS[code];
  return code.startsWith("finance_") ? "placementReasonPackage" : "placementReasonOther";
}

/**
 * A move returns the old booking's visit before the new booking takes one,
 * so a member out of visits can still be moved: only that reason gives way.
 */
export function placementBlocked(option: Pick<ClassPlacementClass, "blocked_reason">, moving: boolean): boolean {
  if (!option.blocked_reason) return false;
  return !(moving && option.blocked_reason === "finance_allowance_exhausted");
}

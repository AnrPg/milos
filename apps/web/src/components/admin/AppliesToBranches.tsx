"use client";

import { useTranslations } from "next-intl";

import type { FacilityLocation } from "@/api/facility";
import { BranchScopePicker } from "@/components/admin/users/BranchScopePicker";
import { membershipLocationScope, type LocationScope } from "@/lib/location-scope";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/** The active branches a staff member may pick (the API already narrows them to their scope). */
export function offeredBranches(locations: FacilityLocation[] | null | undefined) {
  return (locations ?? []).filter((location) => !location.archived_at);
}

/** «Ισχύει για» shows only to people who see at least two active branches. */
export function showsAppliesTo(locations: FacilityLocation[] | null | undefined) {
  return offeredBranches(locations).length >= 2;
}

/**
 * The default «Ισχύει για» of a new item (ADR-186 §8): the page's branch
 * filter when one is set, otherwise every branch the person works at.
 */
export function defaultAppliesTo(locations: FacilityLocation[] | null | undefined, pageFilter: string[] = []) {
  const offered = offeredBranches(locations).map((location) => location.id);
  const fromFilter = pageFilter.filter((id) => offered.includes(id));
  return (fromFilter.length > 0 ? fromFilter : offered).sort();
}

/**
 * «Ισχύει για» chips (ADR-186 §8).
 *
 * - `kind="each"`: a class, class series or appointment slot. One item is
 *   created per chosen branch.
 * - `kind="covering"`: a package, promotion or programme assignment. One
 *   item valid at the chosen branches; «Όλα τα καταστήματα» (future branches
 *   too) is offered only to staff who work at every branch.
 *
 * The server checks every branch again against the person's scope.
 */
export function AppliesToBranches({
  locations,
  value,
  onChange,
  kind,
  disabled = false,
}: {
  locations: FacilityLocation[] | null | undefined;
  value: LocationScope;
  onChange: (value: LocationScope) => void;
  kind: "each" | "covering";
  disabled?: boolean;
}) {
  const t = useTranslations("BranchScope");
  const { membership } = useSelectedMembershipRole();
  const offered = offeredBranches(locations);
  if (offered.length < 2) return null;

  const everywhere = membershipLocationScope(membership) === "all";
  const allowed: LocationScope = kind === "covering" && everywhere ? "all" : offered.map((location) => location.id);

  return (
    <BranchScopePicker
      locations={offered}
      value={value}
      onChange={onChange}
      allowed={allowed}
      disabled={disabled}
      legend={t("appliesTo")}
      help={kind === "each" ? t("appliesToEachHelp") : t("appliesToCoveringHelp")}
    />
  );
}

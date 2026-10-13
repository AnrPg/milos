const OPERATIONAL_SECTIONS = new Set(["overview", "finance", "admin_actions"]);

export function packageSubscriptionLabel(subscription: Record<string, unknown>) {
  const name = subscription.package_name;
  if (typeof name === "string" && name.trim()) return name.trim();

  for (const key of ["package_code_snapshot", "package_family_snapshot"]) {
    const value = subscription[key];
    if (typeof value !== "string" || !value.trim()) continue;

    return value
      .trim()
      .replace(/[_-]+/g, " ")
      .replace(/\b[a-z]/g, (letter) => letter.toUpperCase());
  }
  return "";
}

/**
 * ADR-129: the dossier PR panel's content count. Staff who are not coaches of
 * the gym still get the panel, explaining that PRs are visible to coaches only.
 */
export function prSectionContentCount(
  data: { visibility: "coach" | "coach_role_required"; prs: unknown[] } | undefined,
) {
  if (!data) return 0;
  return data.visibility === "coach_role_required" ? 1 : data.prs.length;
}

export function visibleAdminProfileSections(
  availableSections: string[],
  contentCounts: Record<string, number>,
) {
  return availableSections.filter(
    (section) => OPERATIONAL_SECTIONS.has(section) || (contentCounts[section] ?? 0) > 0,
  );
}

// ADR-097: perk allowances an admin can top up, in the order they are offered.
const PERK_ALLOWANCES = ["event_visits", "guest_passes", "open_gym_visits"] as const;

/**
 * Allowances a personal extension can be granted for: general class visits,
 * per-class-type limits (ADR-096) and the perks the member's plan has (ADR-097).
 * Falls back to class visits when the plan reports no allowance at all.
 */
export function grantableAllowances(allowances: Record<string, unknown> | null | undefined): string[] {
  const keys = Object.keys(allowances ?? {});
  const classKeys = keys
    .filter((key) => key === "class_visits" || key.startsWith("class_visits:"))
    .sort((a, b) => (a === "class_visits" ? -1 : b === "class_visits" ? 1 : a.localeCompare(b)));
  const perkKeys = PERK_ALLOWANCES.filter((key) => keys.includes(key));
  const result = [...classKeys, ...perkKeys];
  return result.length > 0 ? result : ["class_visits"];
}

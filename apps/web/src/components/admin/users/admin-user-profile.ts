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

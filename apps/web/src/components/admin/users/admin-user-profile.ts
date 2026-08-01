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

export function visibleAdminProfileSections(
  availableSections: string[],
  contentCounts: Record<string, number>,
) {
  return availableSections.filter(
    (section) => OPERATIONAL_SECTIONS.has(section) || (contentCounts[section] ?? 0) > 0,
  );
}

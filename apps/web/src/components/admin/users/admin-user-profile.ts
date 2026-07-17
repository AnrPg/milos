const OPERATIONAL_SECTIONS = new Set(["overview", "finance", "admin_actions"]);

export function visibleAdminProfileSections(
  availableSections: string[],
  contentCounts: Record<string, number>,
) {
  return availableSections.filter(
    (section) => OPERATIONAL_SECTIONS.has(section) || (contentCounts[section] ?? 0) > 0,
  );
}

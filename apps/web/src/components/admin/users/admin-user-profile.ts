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

export type DossierMode = "loading" | "full" | "prs_only" | "unavailable";

/**
 * ADR-132: which dossier to render. A coach's client scope (ADR-100) can close
 * the full profile, but every coach of the gym reads members' PRs (ADR-129),
 * so a coach falls back to a PR-only dossier when the profile is refused and
 * the PR endpoint names the person as an active member of the gym.
 */
export function dossierMode(input: {
  profileLoading: boolean;
  profileLoaded: boolean;
  actorCoaches: boolean;
  prsLoading: boolean;
  prs: { visibility: "coach" | "coach_role_required"; member?: unknown } | undefined;
}): DossierMode {
  if (input.profileLoading) return "loading";
  if (input.profileLoaded) return "full";
  if (!input.actorCoaches) return "unavailable";
  if (input.prsLoading) return "loading";
  return input.prs?.visibility === "coach" && input.prs.member ? "prs_only" : "unavailable";
}

/** ADR-132: members matching a nickname search, for the coach's PR shortcut. */
export function filterDossierMembers<T extends { nickname: string }>(members: T[], query: string, limit = 8): T[] {
  const needle = query.trim().toLocaleLowerCase();
  const matches = needle ? members.filter((member) => member.nickname.toLocaleLowerCase().includes(needle)) : members;
  return matches.slice(0, limit);
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

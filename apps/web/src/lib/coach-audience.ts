import type { CoachAudience, CoachRef } from "@/api/journal";

/**
 * «Οι coach μου» per coach (ADR-162, ANR 2026-10-21): the chooser and the
 * setting work on keys (`organization:user`), so a coach who works for two
 * of the member's providers is two choices, one per place.
 */
export function coachKey(ref: CoachRef) {
  return `${ref.organization_id}:${ref.user_id}`;
}

export function keysOf(refs: readonly CoachRef[] | null | undefined) {
  return (refs ?? []).map(coachKey);
}

export function refOf(key: string): CoachRef {
  const [organization_id, user_id] = key.split(":");
  return { organization_id, user_id };
}

export type CoachOption = { key: string; name: string; included: boolean };
export type CoachGroup = {
  organizationId: string;
  provider: string;
  kind: string;
  coaches: CoachOption[];
};

/**
 * The coaches a member can pick, by provider. `homeOrganizationId` (where
 * the entry was recorded) is left out: its coaches always see the entry.
 */
export function coachGroups(audience: CoachAudience | null | undefined, homeOrganizationId?: string | null): CoachGroup[] {
  return (audience?.providers ?? [])
    .filter((provider) => provider.organization_id !== homeOrganizationId)
    .map((provider) => ({
      organizationId: provider.organization_id,
      provider: provider.name,
      kind: provider.kind,
      coaches: (provider.coaches ?? []).map((coach) => ({
        key: coachKey({ organization_id: provider.organization_id, user_id: coach.user_id }),
        name: coach.name ?? provider.name,
        included: coach.included,
      })),
    }))
    .filter((group) => group.coaches.length > 0);
}

export function coachCount(groups: CoachGroup[]) {
  return groups.reduce((sum, group) => sum + group.coaches.length, 0);
}

/** The keys among `keys` that belong to `groups`. */
export function within(keys: readonly string[], groups: CoachGroup[]) {
  const known = new Set(groups.flatMap((group) => group.coaches.map((coach) => coach.key)));
  return keys.filter((key) => known.has(key));
}

/** Toggles one coach, never leaving the choice empty. */
export function toggleCoach(selected: readonly string[], key: string) {
  if (!selected.includes(key)) return [...selected, key];
  return selected.length > 1 ? selected.filter((other) => other !== key) : [...selected];
}

export function sameKeys(a: readonly string[], b: readonly string[]) {
  return a.length === b.length && a.every((key) => b.includes(key));
}

/** The names of the coaches `keys` names, for «Μόνο …». */
export function coachNames(audience: CoachAudience | null | undefined, keys: readonly string[]) {
  return coachGroups(audience)
    .flatMap((group) => group.coaches)
    .filter((coach) => keys.includes(coach.key))
    .map((coach) => coach.name);
}

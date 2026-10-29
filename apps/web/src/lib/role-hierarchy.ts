import { ALL_ROLES, type RoleName } from "@/api/roles";

// The role hierarchy (ADR-099, ADR-219), mirroring MembershipPolicy on the
// API: owner › admin › staff › clients › guests (ADR-272). Roles of one tier
// are peers.
const TIERS: Record<RoleName, number> = {
  owner: 5,
  admin: 4,
  coach: 3,
  front_desk: 3,
  accountant: 3,
  janitor: 3,
  member: 2,
  athlete: 2,
  guest: 1,
};

export function roleTier(role: string): number {
  return TIERS[role as RoleName] ?? 0;
}

/** The rank of a set's most privileged role (0 for none). */
export function topTier(roles: readonly string[]): number {
  return roles.reduce((top, role) => Math.max(top, roleTier(role)), 0);
}

/** Which roles the signed-in person may hand out to others. */
export function grantableRoles(actorRoles: readonly string[]): RoleName[] {
  if (actorRoles.includes("owner")) return ALL_ROLES;
  if (actorRoles.includes("admin")) return ALL_ROLES.filter((role) => role !== "owner" && role !== "admin");
  return [];
}

/** People act only on those ranked below them; owners also on co-owners. */
export function canManageMember(actorRoles: readonly string[], targetRoles: readonly string[]): boolean {
  return (
    topTier(actorRoles) > topTier(targetRoles) || (actorRoles.includes("owner") && targetRoles.includes("owner"))
  );
}

/**
 * Roles someone may add or drop on themselves: those below their top role.
 * Nobody makes themselves a guest (staff do, ADR-272).
 */
export function selfAssignableRoles(ownRoles: readonly string[]): RoleName[] {
  const top = topTier(ownRoles);
  return ALL_ROLES.filter((role) => role !== "guest" && roleTier(role) < top);
}

/** The roles `actorRoles` may toggle on someone holding `targetRoles`. */
export function editableRoles(actorRoles: readonly string[], targetRoles: readonly string[], self: boolean): RoleName[] {
  if (self) return selfAssignableRoles(targetRoles);
  return canManageMember(actorRoles, targetRoles) ? grantableRoles(actorRoles) : [];
}

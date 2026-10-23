// Branch scope of a staff membership (ADR-186): every branch («Όλα τα
// καταστήματα») or a list of the business's locations. The API enforces it;
// these helpers only decide what the pickers offer.

export type LocationScopePayload = { all_locations: boolean; location_ids: string[] };

/** "all" or the sorted branch ids. */
export type LocationScope = "all" | string[];

export function toLocationScope(payload: LocationScopePayload | null | undefined): LocationScope {
  if (!payload || payload.all_locations) return "all";
  return Array.from(new Set(payload.location_ids)).sort();
}

export function toPayload(scope: LocationScope): LocationScopePayload {
  return scope === "all" ? { all_locations: true, location_ids: [] } : { all_locations: false, location_ids: scope };
}

/** The signed-in membership's own scope; anything without one works everywhere. */
export function membershipLocationScope(membership: { location_scope?: LocationScopePayload | null } | null | undefined) {
  return toLocationScope(membership?.location_scope);
}

export function coversLocation(scope: LocationScope, locationId: string | null | undefined) {
  if (scope === "all") return true;
  return Boolean(locationId) && scope.includes(locationId!);
}

/** Nobody grants a scope wider than their own (mirrors LocationScopePolicy). */
export function canGrantScope(granter: LocationScope, target: LocationScope) {
  if (granter === "all") return true;
  if (target === "all" || target.length === 0) return false;
  return target.every((id) => granter.includes(id));
}

export function sameScope(a: LocationScope, b: LocationScope) {
  if (a === "all" || b === "all") return a === b;
  return [...a].sort().join() === [...b].sort().join();
}

/** Branch pickers appear only for businesses with more than one active branch. */
export function hasSeveralBranches(locations: { archived_at?: string | null }[] | null | undefined) {
  return (locations ?? []).filter((location) => !location.archived_at).length > 1;
}

import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import type { AtlasRange } from "@/lib/anatomy/atlas";

/**
 * The anatomy atlas (ADR-164): the member's own muscle coverage across every
 * provider (account read model) and, for one node, the exercises that train
 * it with the current gym's videos.
 */
export type MyAtlas = components["schemas"]["MyAtlas"];
export type AtlasNodeCoverage = components["schemas"]["AtlasNodeCoverage"];
export type AtlasNodeExercises = components["schemas"]["AtlasNodeExercises"];
export type AtlasNodeExercise = components["schemas"]["AtlasNodeExercise"];

export const myAtlasKey = (range: AtlasRange) => ["me", "atlas", range] as const;
export const atlasNodeExercisesKey = (nodeId: string) => ["anatomy", "nodes", nodeId, "exercises"] as const;

export function fetchMyAtlas(token: string, range: AtlasRange) {
  return apiRequest<MyAtlas>(`/me/atlas?range=${encodeURIComponent(range)}`, { token, scope: "account" });
}

/** Org-scoped: the gym the member is looking at (the selected provider). */
export function fetchAtlasNodeExercises(token: string, nodeId: string) {
  return apiRequest<AtlasNodeExercises>(`/anatomy/nodes/${encodeURIComponent(nodeId)}/exercises`, { token });
}

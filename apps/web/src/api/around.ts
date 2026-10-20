import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Γύρω μου (ADR-154): what is near a signed-in person, by kind, with one
 * versioned filter shared by the search, «Δες όλα» pages, map pins and saved
 * filters. All personal routes: none of these go through a gym.
 */
export type AroundFilterRequest = components["schemas"]["AroundFilter"];
export type AroundNormalizedFilter = components["schemas"]["AroundNormalizedFilter"];
export type AroundOriginRequest = components["schemas"]["AroundOriginRequest"];
export type AroundOrigin = components["schemas"]["AroundOrigin"];
export type AroundSearchRequest = components["schemas"]["AroundSearchRequest"];
export type AroundSearchResponse = components["schemas"]["AroundSearchResponse"];
export type AroundSections = AroundSearchResponse["sections"];
export type AroundKindResponse = components["schemas"]["AroundKindResponse"];
export type AroundPinsResponse = components["schemas"]["AroundPinsResponse"];
export type AroundPin = components["schemas"]["AroundPin"];
export type AroundViewport = components["schemas"]["AroundViewport"];
export type AroundWider = components["schemas"]["AroundWiderCount"];
export type AroundKind = AroundPin["kind"];
export type AroundEventItem = components["schemas"]["AroundEventItem"];
export type AroundBoxItem = components["schemas"]["AroundBoxItem"];
export type AroundClubItem = components["schemas"]["AroundClubItem"];
export type AroundPostItem = components["schemas"]["AroundPostItem"];
export type AroundItem = AroundEventItem | AroundBoxItem | AroundClubItem | AroundPostItem;
export type Neighbourhood = components["schemas"]["Neighbourhood"];
export type AroundVisibility = components["schemas"]["AroundVisibility"];

export const AROUND_KINDS: AroundKind[] = ["events", "boxes", "clubs", "posts"];

export const AROUND_KEY = ["around"] as const;
export const AROUND_AREA_KEY = ["around", "area"] as const;
export const neighbourhoodsKey = (q: string) => ["around", "neighbourhoods", q] as const;

export function searchAround(token: string, body: AroundSearchRequest, signal?: AbortSignal) {
  return apiRequest<AroundSearchResponse>("/around/search", { method: "POST", token, body, signal });
}

export function searchAroundKind(
  token: string,
  kind: AroundKind,
  body: components["schemas"]["AroundKindRequest"],
  signal?: AbortSignal,
) {
  return apiRequest<AroundKindResponse>(`/around/search/${encodeURIComponent(kind)}`, { method: "POST", token, body, signal });
}

export function fetchAroundPins(token: string, bbox: AroundViewport, filter: AroundFilterRequest, signal?: AbortSignal) {
  return apiRequest<AroundPinsResponse>("/around/pins", { method: "POST", token, body: { bbox, filter }, signal });
}

export async function searchNeighbourhoods(token: string, q: string, signal?: AbortSignal) {
  const data = await apiRequest<components["schemas"]["NeighbourhoodsResponse"]>(
    `/places/neighbourhoods?q=${encodeURIComponent(q)}`,
    { token, signal },
  );
  return data.neighbourhoods ?? [];
}

export async function fetchAroundArea(token: string) {
  const data = await apiRequest<components["schemas"]["AroundAreaResponse"]>("/me/around/area", { token });
  return data.neighbourhoods ?? [];
}

/** «Η περιοχή μου»: up to 5 places, the first is the main one. */
export async function saveAroundArea(token: string, neighbourhoodIds: string[]) {
  const data = await apiRequest<components["schemas"]["AroundAreaResponse"]>("/me/around/area", {
    method: "PUT",
    token,
    body: { neighbourhood_ids: neighbourhoodIds },
  });
  return data.neighbourhoods ?? [];
}

/** «Φαίνομαι στο Γύρω μου»: public posts at the main neighbourhood, or not. */
export function setAroundVisibility(token: string, visible: boolean) {
  return apiRequest<AroundVisibility>("/me/social/around-visibility", { method: "PUT", token, body: { visible } });
}

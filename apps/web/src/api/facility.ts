import { apiRequest } from "@/api/client";

/** A gym location of the Facility context (ADR-097). */
export type FacilityLocation = {
  id: string;
  name: string;
  address: string | null;
  archived_at: string | null;
};

/** All locations, archived ones included, for admin screens. */
export async function listAdminLocations(token: string) {
  const response = await apiRequest<{ locations: FacilityLocation[] }>("/admin/locations", { token });
  return response.locations;
}

export async function createLocation(token: string, payload: { name: string; address?: string | null }) {
  const response = await apiRequest<{ location: FacilityLocation }>("/admin/locations", {
    method: "POST",
    token,
    body: payload,
  });
  return response.location;
}

export async function updateLocation(
  token: string,
  id: string,
  payload: { name?: string; address?: string | null },
) {
  const response = await apiRequest<{ location: FacilityLocation }>(`/admin/locations/${id}`, {
    method: "PATCH",
    token,
    body: payload,
  });
  return response.location;
}

/** Archived locations stay on past records but can no longer be chosen. */
export async function archiveLocation(token: string, id: string) {
  const response = await apiRequest<{ location: FacilityLocation }>(`/admin/locations/${id}/archive`, {
    method: "POST",
    token,
  });
  return response.location;
}

/** An open-gym visit recorded by the member's own scan or at the desk. */
export type FacilityCheckIn = {
  id: string;
  user_id: string;
  nickname?: string | null;
  location_id?: string | null;
  location_name?: string | null;
  checked_in_on: string;
  checked_in_at: string;
  source: "self" | "staff";
  recorded_by_id?: string | null;
  /** True when the member had already checked in that day; no visit is used twice. */
  already_checked_in?: boolean;
};

export async function listCheckIns(token: string, params: { date?: string; userId?: string } = {}) {
  const search = new URLSearchParams();
  if (params.date) search.set("date", params.date);
  if (params.userId) search.set("user_id", params.userId);
  const suffix = search.size > 0 ? `?${search.toString()}` : "";
  const response = await apiRequest<{ check_ins: FacilityCheckIn[] }>(`/admin/check-ins${suffix}`, { token });
  return response.check_ins;
}

export async function createCheckIn(token: string, payload: { user_id: string; location_id?: string | null }) {
  const response = await apiRequest<{ check_in: FacilityCheckIn }>("/admin/check-ins", {
    method: "POST",
    token,
    body: payload,
  });
  return response.check_in;
}

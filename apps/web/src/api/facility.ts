import { apiRequest } from "@/api/client";

/** One weekly opening span (ADR-141): ISO weekday (Monday = 1), "HH:MM" times. */
export type OpeningHoursSpan = { weekday: number; opens: string; closes: string };

/** A gym location of the Facility context (ADR-097), placed on the map (ADR-141). */
export type FacilityLocation = {
  id: string;
  name: string;
  address: string | null;
  latitude?: number | null;
  longitude?: number | null;
  neighbourhood?: string | null;
  city?: string | null;
  country_code?: string | null;
  opening_hours?: OpeningHoursSpan[];
  archived_at: string | null;
};

export type LocationPayload = {
  name?: string;
  address?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  neighbourhood?: string | null;
  city?: string | null;
  country_code?: string | null;
  opening_hours?: OpeningHoursSpan[];
};

/** An address suggestion from the geocoder (ADR-141). */
export type GeocodePlace = {
  label: string;
  address: string | null;
  neighbourhood: string | null;
  city: string | null;
  country_code: string | null;
  latitude: number;
  longitude: number;
};

export async function searchAddresses(
  token: string,
  query: string,
  options: { language?: string; near?: { latitude: number; longitude: number } | null } = {},
) {
  const search = new URLSearchParams({ q: query });
  if (options.language) search.set("language", options.language);
  if (options.near) {
    search.set("near_latitude", String(options.near.latitude));
    search.set("near_longitude", String(options.near.longitude));
  }
  const response = await apiRequest<{ places: GeocodePlace[] }>(`/admin/geocode?${search.toString()}`, {
    token,
  });
  return response.places;
}

/** Whether pasted text is a Google Maps link rather than an address. */
export function isMapLink(text: string) {
  return /^https?:\/\/((maps\.app\.)?goo\.gl|g\.co|((www|maps)\.)?google\.[a-z.]{2,6})\//i.test(text.trim());
}

/** The pin and address behind a pasted Google Maps link, short links included. */
export async function resolveMapLink(token: string, url: string, language?: string) {
  const search = new URLSearchParams({ url: url.trim() });
  if (language) search.set("language", language);
  const response = await apiRequest<{ place: GeocodePlace }>(`/admin/geocode/link?${search.toString()}`, { token });
  return response.place;
}

export async function reverseGeocode(token: string, latitude: number, longitude: number, language?: string) {
  const search = new URLSearchParams({ latitude: String(latitude), longitude: String(longitude) });
  if (language) search.set("language", language);
  const response = await apiRequest<{ place: GeocodePlace | null }>(`/admin/geocode/reverse?${search.toString()}`, {
    token,
  });
  return response.place;
}

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

export async function updateLocation(token: string, id: string, payload: LocationPayload) {
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

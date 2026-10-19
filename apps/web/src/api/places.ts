import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

type PlacesResponse = paths["/api/me/places"]["get"]["responses"][200]["content"]["application/json"];

/** A location the user can book, across their gyms (Πρόγραμμα location picker). */
export type BookablePlace = PlacesResponse["places"][number];

export async function fetchBookablePlaces(token: string, near?: { latitude: number; longitude: number } | null) {
  const search = near ? `?lat=${near.latitude}&lng=${near.longitude}` : "";
  const response = await apiRequest<PlacesResponse>(`/me/places${search}`, { token });
  return response.places;
}

/** Sets (or, with null, clears) the user's home location in the current gym. */
export async function setMyHomeLocation(token: string, locationId: string | null) {
  return apiRequest<{ membership: { user_id: string; home_location_id: string | null } }>("/me/home-location", {
    method: "PUT",
    token,
    body: { location_id: locationId },
  });
}

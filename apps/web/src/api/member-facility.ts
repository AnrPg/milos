import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

type CheckInOperation = paths["/api/org/{organization_slug}/check-ins"]["post"];

export type MemberCheckIn =
  CheckInOperation["responses"][201]["content"]["application/json"]["check_in"];

export type MemberLocation = {
  id: string;
  name: string;
  address: string | null;
  archived_at: string | null;
};

/** Active locations of the gym (ADR-097). */
export async function listMemberLocations(token: string) {
  const response = await apiRequest<{ locations: MemberLocation[] }>("/locations", { token });
  return Array.isArray(response.locations) ? response.locations : [];
}

/** Open-gym self check-in; a second call on the same day returns `already_checked_in`. */
export async function checkInOpenGym(token: string, locationId: string | null) {
  const response = await apiRequest<{ check_in: MemberCheckIn }>("/check-ins", {
    method: "POST",
    token,
    body: locationId ? { location_id: locationId } : {},
  });

  return response.check_in;
}

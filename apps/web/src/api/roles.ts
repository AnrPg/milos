import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// Role sets, head coach, role access and the owner's gym actions (ADR-099,
// ADR-100); coaching relationships and private coach notes (ADR-100, ADR-101);
// the cleaning log (ADR-102).

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;
type Op = operations;

type MembershipRolesResponse = Json<Op["PaleeWeb.AdminUserController.update_roles"]["responses"][200]>;
type RoleAccessResponse = Json<Op["PaleeWeb.RoleAccessController.show"]["responses"][200]>;
type OwnedOrganization = Json<Op["PaleeWeb.OwnerOrganizationController.create"]["responses"][201]>;
type RelationshipsResponse = Json<Op["PaleeWeb.CoachingRelationshipsController.index"]["responses"][200]>;
type RelationshipResponse = Json<Op["PaleeWeb.CoachingRelationshipsController.create"]["responses"][201]>;
type NotesResponse = Json<Op["PaleeWeb.CoachNotesController.index"]["responses"][200]>;
type NoteResponse = Json<Op["PaleeWeb.CoachNotesController.create"]["responses"][201]>;
type ReadsResponse = Json<Op["PaleeWeb.CoachNotesController.reads"]["responses"][200]>;
type AreasResponse = Json<Op["PaleeWeb.CleaningController.areas"]["responses"][200]>;
type AreaResponse = Json<Op["PaleeWeb.CleaningController.create_area"]["responses"][201]>;
type EntriesResponse = Json<Op["PaleeWeb.CleaningController.entries"]["responses"][200]>;
type EntryResponse = Json<Op["PaleeWeb.CleaningController.start"]["responses"][201]>;
type MembershipStatusResponse = Json<Op["PaleeWeb.AdminUserController.membership_status"]["responses"][200]>;
type LocationScopeResponse = Json<Op["PaleeWeb.StaffLocationScopeController.update"]["responses"][200]>;

export type MembershipRoles = MembershipRolesResponse["membership"];
export type RoleName = "owner" | "admin" | "coach" | "front_desk" | "accountant" | "janitor" | "member" | "athlete" | "guest";
export type RoleAccess = RoleAccessResponse;
export type CoachingRelationship = RelationshipsResponse["relationships"][number];
export type CoachNote = NotesResponse["notes"][number];
export type CoachNoteRead = ReadsResponse["reads"][number];
/** What a coach note is about, when it is about one thing (ADR-140 §5). */
export type CoachNoteSubjectKind = NonNullable<CoachNote["subject_kind"]>;
export type CoachNoteSubject = { kind: CoachNoteSubjectKind; id: string };
export type CleaningArea = AreasResponse["areas"][number];
export type CleaningEntry = EntriesResponse["entries"][number];
export type MembershipStatus = MembershipStatusResponse["membership_status"];

export const ALL_ROLES: RoleName[] = [
  "owner",
  "admin",
  "coach",
  "front_desk",
  "accountant",
  "janitor",
  "member",
  "athlete",
  // ADR-272: a guest of the box, the lowest client-type role.
  "guest",
];

export async function updateMemberRoles(token: string, userId: string, roles: RoleName[]) {
  const response = await apiRequest<MembershipRolesResponse>(`/admin/users/${userId}/roles`, {
    method: "PUT",
    token,
    body: { roles },
  });
  return response.membership;
}

type MyRolesResponse = Json<Op["PaleeWeb.MyRolesController.update"]["responses"][200]>;

/** Settings › My roles: roles below my top role in this box (ADR-219). */
export async function updateMyRoles(token: string, roles: RoleName[]) {
  const response = await apiRequest<MyRolesResponse>("/me/roles", { method: "PUT", token, body: { roles } });
  return response.membership;
}

export async function updateCoachScope(token: string, userId: string, coachScope: "own" | "all") {
  const response = await apiRequest<MembershipRolesResponse>(`/admin/users/${userId}/coach-scope`, {
    method: "PATCH",
    token,
    body: { coach_scope: coachScope },
  });
  return response.membership;
}

/** The branches a staff member works at (ADR-186); `null` means every branch. */
export async function updateLocationScope(token: string, userId: string, locationIds: string[] | null) {
  const response = await apiRequest<LocationScopeResponse>(`/admin/users/${userId}/location-scope`, {
    method: "PUT",
    token,
    body: locationIds === null ? { all_locations: true } : { all_locations: false, location_ids: locationIds },
  });
  return response.location_scope;
}

export async function fetchMembershipStatus(token: string, userId: string) {
  const response = await apiRequest<MembershipStatusResponse>(`/admin/users/${userId}/membership-status`, { token });
  return response.membership_status;
}

export async function fetchRoleAccess(token: string) {
  return apiRequest<RoleAccessResponse>("/admin/role-access", { token });
}

export async function updateRoleAccess(token: string, role: string, capabilities: string[]) {
  return apiRequest<RoleAccessResponse>(`/admin/role-access/${role}`, {
    method: "PUT",
    token,
    body: { capabilities },
  });
}

export async function createOwnedOrganization(token: string, name: string) {
  return apiRequest<OwnedOrganization>("/organizations", { method: "POST", token, body: { name } });
}

export async function transferOwnership(token: string, userId: string) {
  return apiRequest<OwnedOrganization>("/admin/organization/transfer", {
    method: "POST",
    token,
    body: { user_id: userId },
  });
}

export async function archiveOrganization(token: string, confirm: string) {
  return apiRequest<OwnedOrganization>("/admin/organization/archive", {
    method: "POST",
    token,
    body: { confirm },
  });
}

export type MyClientStats = {
  client_count: number;
  coaching_messages_this_week: number;
  awaiting_reply: number;
};

/** Πελάτες μου stats for the signed-in coach (ADR-140 §7). */
export async function fetchMyClientStats(token: string) {
  return apiRequest<MyClientStats>("/staff/my-client-stats", { token });
}

export async function fetchCoachingRelationships(token: string, filter: { coachUserId?: string; clientUserId?: string } = {}) {
  const params = new URLSearchParams();
  if (filter.coachUserId) params.set("coach_user_id", filter.coachUserId);
  if (filter.clientUserId) params.set("client_user_id", filter.clientUserId);
  const suffix = params.size > 0 ? `?${params.toString()}` : "";
  const response = await apiRequest<RelationshipsResponse>(`/staff/coaching-relationships${suffix}`, { token });
  return response.relationships;
}

/** Without `coachUserId` a coach takes the athlete themselves. */
export async function startCoachingRelationship(token: string, clientUserId: string, coachUserId?: string) {
  const response = await apiRequest<RelationshipResponse>("/staff/coaching-relationships", {
    method: "POST",
    token,
    body: { client_user_id: clientUserId, ...(coachUserId ? { coach_user_id: coachUserId } : {}) },
  });
  return response.relationship;
}

export async function endCoachingRelationship(token: string, id: string) {
  await apiRequest<unknown>(`/staff/coaching-relationships/${id}/end`, { method: "POST", token });
}

export async function fetchCoachNotes(token: string, clientUserId: string) {
  const response = await apiRequest<NotesResponse>(`/staff/clients/${clientUserId}/coach-notes`, { token });
  return response.notes;
}

export async function createCoachNote(token: string, clientUserId: string, body: string, subject?: CoachNoteSubject | null) {
  const response = await apiRequest<NoteResponse>(`/staff/clients/${clientUserId}/coach-notes`, {
    method: "POST",
    token,
    body: { body, ...(subject ? { subject_kind: subject.kind, subject_id: subject.id } : {}) },
  });
  return response.note;
}

export async function updateCoachNote(token: string, id: string, body: string) {
  const response = await apiRequest<NoteResponse>(`/staff/coach-notes/${id}`, { method: "PATCH", token, body: { body } });
  return response.note;
}

export async function deleteCoachNote(token: string, id: string) {
  await apiRequest<unknown>(`/staff/coach-notes/${id}`, { method: "DELETE", token });
}

export async function fetchCoachNoteReads(token: string) {
  const response = await apiRequest<ReadsResponse>("/staff/coach-notes/reads", { token });
  return response.reads;
}

export async function setNotesVisibility(token: string, visibleToAdmins: boolean) {
  return apiRequest<{ visible_to_admins: boolean }>("/staff/me/notes-visibility", {
    method: "PUT",
    token,
    body: { visible_to_admins: visibleToAdmins },
  });
}

export async function fetchCleaningAreas(token: string) {
  const response = await apiRequest<AreasResponse>("/staff/cleaning/areas", { token });
  return response.areas;
}

export async function createCleaningArea(token: string, body: { name: string; tasks: string[] }) {
  const response = await apiRequest<AreaResponse>("/staff/cleaning/areas", { method: "POST", token, body });
  return response.area;
}

export async function updateCleaningArea(token: string, id: string, body: { name?: string; tasks?: string[] }) {
  const response = await apiRequest<AreaResponse>(`/staff/cleaning/areas/${id}`, { method: "PATCH", token, body });
  return response.area;
}

export async function archiveCleaningArea(token: string, id: string) {
  const response = await apiRequest<AreaResponse>(`/staff/cleaning/areas/${id}/archive`, { method: "POST", token });
  return response.area;
}

export async function fetchCleaningEntries(token: string) {
  const response = await apiRequest<EntriesResponse>("/staff/cleaning/entries", { token });
  return response.entries;
}

export async function startCleaning(token: string, areaId: string) {
  const response = await apiRequest<EntryResponse>("/staff/cleaning/entries", { method: "POST", token, body: { area_id: areaId } });
  return response.entry;
}

export async function finishCleaning(
  token: string,
  id: string,
  body: {
    tasks_done: string[];
    note?: string | null;
    /** ADR-290: an answer per cleaning point of the room. */
    point_results?: { point_id: string; status: "cleaned" | "not_cleaned"; note?: string | null; after_media_id?: string | null }[];
  },
) {
  const response = await apiRequest<EntryResponse>(`/staff/cleaning/entries/${id}/finish`, { method: "POST", token, body });
  return response.entry;
}

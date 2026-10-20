import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Κοινότητα for staff (ADR-143, board 7 Q3, Q5, Q6): the member-groups
 * setting, groups waiting for approval, the grouped report queue and the
 * box's open clubs. Calls go through the selected gym (`/admin`).
 */
export type StaffGroup = components["schemas"]["CommunityStaffGroup"];
export type StaffGroups = components["schemas"]["CommunityStaffGroupsResponse"];
export type MemberGroupsSetting = StaffGroups["settings"]["member_groups"];
export type ReportRow = components["schemas"]["CommunityReportRow"];
export type ReportAction = components["schemas"]["CommunityReportActionRequest"]["action"];
export type StaffOpenClub = components["schemas"]["CommunityOpenClub"];
export type OpenClubDraft = components["schemas"]["CommunityOpenClubRequest"];

export const MEMBER_GROUP_OPTIONS: MemberGroupsSetting[] = ["none", "approval", "free"];

/** What staff can do with a reported item of each kind (board 7 Q5). */
export const REPORT_ACTIONS: Record<ReportRow["target_type"], ReportAction[]> = {
  post: ["hide", "delete", "dismiss"],
  comment: ["hide", "delete", "dismiss"],
  channel: ["archive", "dismiss"],
};

export const STAFF_GROUPS_KEY = ["admin", "community", "groups"] as const;
export const REPORTS_KEY = ["admin", "community", "reports"] as const;
export const STAFF_CLUBS_KEY = ["admin", "community", "clubs"] as const;
export const staffClubKey = (id: string) => ["admin", "community", "clubs", id] as const;

const BASE = "/admin/community";
const id = (value: string) => encodeURIComponent(value);

export function fetchStaffGroups(token: string) {
  return apiRequest<StaffGroups>(`${BASE}/groups`, { token });
}

export async function decideGroup(token: string, groupId: string, decision: "approve" | "decline") {
  const data = await apiRequest<{ group: StaffGroup }>(`${BASE}/groups/${id(groupId)}/decision`, {
    method: "PUT",
    token,
    body: { decision },
  });
  return data.group;
}

export async function reopenStaffGroup(token: string, groupId: string) {
  const data = await apiRequest<{ group: StaffGroup }>(`${BASE}/groups/${id(groupId)}/reopen`, { method: "POST", token });
  return data.group;
}

export function updateCommunitySettings(token: string, memberGroups: MemberGroupsSetting) {
  return apiRequest<{ member_groups: MemberGroupsSetting; lifecycle: StaffGroups["settings"]["lifecycle"] }>(
    `${BASE}/settings`,
    { method: "PUT", token, body: { member_groups: memberGroups } },
  );
}

export async function fetchReports(token: string) {
  const data = await apiRequest<{ reports: ReportRow[] }>(`${BASE}/reports`, { token });
  return data.reports;
}

export function actOnReport(token: string, row: Pick<ReportRow, "target_type" | "target_id">, action: ReportAction) {
  return apiRequest<{ resolved: number }>(`${BASE}/reports/actions`, {
    method: "POST",
    token,
    body: { target_type: row.target_type, target_id: row.target_id, action },
  });
}

export async function fetchStaffClubs(token: string) {
  const data = await apiRequest<{ clubs: StaffOpenClub[] }>(`${BASE}/clubs`, { token });
  return data.clubs;
}

export async function fetchStaffClub(token: string, clubId: string) {
  const data = await apiRequest<{ club: StaffOpenClub }>(`${BASE}/clubs/${id(clubId)}`, { token });
  return data.club;
}

export async function createOpenClub(token: string, draft: OpenClubDraft) {
  const data = await apiRequest<{ club: StaffOpenClub }>(`${BASE}/clubs`, { method: "POST", token, body: draft });
  return data.club;
}

export async function updateOpenClub(token: string, clubId: string, draft: Partial<OpenClubDraft>) {
  const data = await apiRequest<{ club: StaffOpenClub }>(`${BASE}/clubs/${id(clubId)}`, {
    method: "PATCH",
    token,
    body: draft,
  });
  return data.club;
}

export function archiveOpenClub(token: string, clubId: string) {
  return apiRequest<{ club_id: string; archived: boolean }>(`${BASE}/clubs/${id(clubId)}/archive`, { method: "POST", token });
}

export async function answerClubRequest(token: string, clubId: string, userId: string, approve: boolean) {
  const data = await apiRequest<{ club: StaffOpenClub }>(`${BASE}/clubs/${id(clubId)}/requests/${id(userId)}`, {
    method: "PUT",
    token,
    body: { approve },
  });
  return data.club;
}

export async function removeClubMember(token: string, clubId: string, userId: string) {
  const data = await apiRequest<{ club: StaffOpenClub }>(`${BASE}/clubs/${id(clubId)}/members/${id(userId)}`, {
    method: "DELETE",
    token,
  });
  return data.club;
}

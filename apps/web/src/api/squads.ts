import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * PT squads (ADR-168): a coach's invite-only channel with their own clients,
 * in the gym's club. Every call goes to the gym that runs the club.
 */
export type PtSquad = components["schemas"]["PtSquad"];
export type PtSquadMember = components["schemas"]["PtSquadMember"];
export type PtSquadsOverview = components["schemas"]["PtSquadsOverview"];
export type PtSquadPerson = PtSquadsOverview["clients"][number];
export type PtSquadDraft = components["schemas"]["PtSquadCreateRequest"];
export type PtSquadOutcome = components["schemas"]["PtSquadOutcome"];

export const squadsKey = (slug: string) => ["community", "squads", slug] as const;
export const squadKey = (squadId: string) => ["community", "squad", squadId] as const;

const base = (slug: string) => `/org/${encodeURIComponent(slug)}/community/squads`;
const id = (value: string) => encodeURIComponent(value);

export function fetchSquads(token: string, slug: string) {
  return apiRequest<PtSquadsOverview>(base(slug), { token });
}

export async function fetchSquad(token: string, slug: string, squadId: string) {
  const data = await apiRequest<{ squad: PtSquad }>(`${base(slug)}/${id(squadId)}`, { token });
  return data.squad;
}

export async function createSquad(token: string, slug: string, draft: PtSquadDraft) {
  const data = await apiRequest<{ squad: PtSquad }>(base(slug), { method: "POST", token, body: draft });
  return data.squad;
}

export async function updateSquad(token: string, slug: string, squadId: string, draft: { name?: string; description?: string | null }) {
  const data = await apiRequest<{ squad: PtSquad }>(`${base(slug)}/${id(squadId)}`, { method: "PATCH", token, body: draft });
  return data.squad;
}

export async function inviteToSquad(token: string, slug: string, squadId: string, userIds: string[]) {
  const data = await apiRequest<{ squad: PtSquad }>(`${base(slug)}/${id(squadId)}/invites`, {
    method: "POST",
    token,
    body: { user_ids: userIds },
  });
  return data.squad;
}

/** Accepting returns the squad; declining returns the outcome. */
export function answerSquadInvite(token: string, slug: string, squadId: string, accept: boolean) {
  return apiRequest<{ squad: PtSquad } | PtSquadOutcome>(`${base(slug)}/${id(squadId)}/invite`, {
    method: "PUT",
    token,
    body: { accept },
  });
}

export function leaveSquad(token: string, slug: string, squadId: string) {
  return apiRequest<PtSquadOutcome>(`${base(slug)}/${id(squadId)}/membership`, { method: "DELETE", token });
}

export async function removeFromSquad(token: string, slug: string, squadId: string, userId: string) {
  const data = await apiRequest<{ squad: PtSquad }>(`${base(slug)}/${id(squadId)}/members/${id(userId)}`, {
    method: "DELETE",
    token,
  });
  return data.squad;
}

export function archiveSquad(token: string, slug: string, squadId: string) {
  return apiRequest<PtSquadOutcome>(`${base(slug)}/${id(squadId)}/archive`, { method: "POST", token });
}

export async function reopenSquad(token: string, slug: string, squadId: string) {
  const data = await apiRequest<{ squad: PtSquad }>(`${base(slug)}/${id(squadId)}/reopen`, { method: "POST", token });
  return data.squad;
}

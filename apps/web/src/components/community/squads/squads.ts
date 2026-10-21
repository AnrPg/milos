import type { PtSquad, PtSquadMember, PtSquadPerson, PtSquadsOverview } from "@/api/squads";

/** Pure helpers for PT squads (ADR-168). */

export function squadHref(clubId: string, squadId: string) {
  return `/clubs/${encodeURIComponent(clubId)}/squads/${encodeURIComponent(squadId)}`;
}

/** The coach's clients not yet in the squad nor invited, by name. */
export function invitableClients(clients: PtSquadPerson[], members: PtSquadMember[] = []) {
  const taken = new Set(members.map((member) => member.person.id));
  return clients
    .filter((client) => !taken.has(client.id))
    .sort((a, b) => (a.nickname ?? "").localeCompare(b.nickname ?? ""));
}

/** How many more people the squad takes. */
export function seatsLeft(squad: Pick<PtSquad, "member_count" | "invite_count">, maxMembers: number) {
  return Math.max(0, maxMembers - squad.member_count - squad.invite_count);
}

/** Whether a squads block has anything to show this person. */
export function hasSquadContent(overview: PtSquadsOverview | undefined, showCoach: boolean) {
  if (!overview) return false;
  if (overview.invites.length > 0 || overview.joined.length > 0) return true;
  return showCoach && overview.can_create;
}

export function matchesQuery(person: PtSquadPerson, query: string) {
  const needle = query.trim().toLocaleLowerCase();
  return needle === "" || (person.nickname ?? "").toLocaleLowerCase().includes(needle);
}

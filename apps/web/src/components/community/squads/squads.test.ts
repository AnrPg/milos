import { describe, expect, it } from "vitest";

import type { PtSquadsOverview } from "@/api/squads";

import { hasSquadContent, invitableClients, matchesQuery, seatsLeft, squadHref } from "./squads";

const person = (id: string, nickname: string | null) => ({ id, nickname, avatar_url: null });

const overview = (patch: Partial<PtSquadsOverview> = {}): PtSquadsOverview => ({
  organization_id: "org",
  can_create: false,
  limits: { max_members: 30, max_live_squads: 20 },
  coached: [],
  archived: [],
  joined: [],
  invites: [],
  clients: [],
  ...patch,
});

describe("squads", () => {
  it("links to the squad inside its club", () => {
    expect(squadHref("club 1", "s/1")).toBe("/clubs/club%201/squads/s%2F1");
  });

  it("offers the clients not already in or invited, by name", () => {
    const clients = [person("b", "Βασίλης"), person("a", "Άννα"), person("c", "Γιώργος")];
    const members = [{ person: person("c", "Γιώργος"), status: "invited" as const, since: "2026-10-21T10:00:00Z" }];
    expect(invitableClients(clients, members).map((client) => client.id)).toEqual(["a", "b"]);
  });

  it("counts the seats left, members and open invitations alike", () => {
    expect(seatsLeft({ member_count: 4, invite_count: 2 }, 30)).toBe(24);
    expect(seatsLeft({ member_count: 29, invite_count: 3 }, 30)).toBe(0);
  });

  it("shows a squads block only with something in it", () => {
    expect(hasSquadContent(undefined, true)).toBe(false);
    expect(hasSquadContent(overview(), true)).toBe(false);
    expect(hasSquadContent(overview({ can_create: true }), true)).toBe(true);
    expect(hasSquadContent(overview({ can_create: true }), false)).toBe(false);
    expect(hasSquadContent(overview({ invites: [{} as never] }), false)).toBe(true);
  });

  it("filters people by name", () => {
    expect(matchesQuery(person("a", "Άννα Κ."), " άννα ")).toBe(true);
    expect(matchesQuery(person("a", null), "x")).toBe(false);
    expect(matchesQuery(person("a", null), "")).toBe(true);
  });
});

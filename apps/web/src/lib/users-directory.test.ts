import { describe, expect, it } from "vitest";

import type { AdminUserDirectoryEntry } from "@/api/admin-users";
import { avatarTone, filterDirectory, initialsOf, roleCounts } from "./users-directory";

const user = (overrides: Partial<AdminUserDirectoryEntry>): AdminUserDirectoryEntry => ({
  id: "id",
  nickname: "name",
  avatar_url: null,
  role: "member",
  account_status: "active",
  joined_at: "2026-01-01T00:00:00Z",
  finance_status: null,
  attention_count: 0,
  ...overrides,
});

const users = [
  user({ id: "1", nickname: "Ελένη", role: "athlete", joined_at: "2026-03-01T00:00:00Z", finance_status: "active" }),
  user({ id: "2", nickname: "bob", role: "member", joined_at: "2026-05-01T00:00:00Z" }),
  user({ id: "3", nickname: "Alice", role: "admin", joined_at: "2026-01-01T00:00:00Z" }),
];

describe("users directory", () => {
  it("counts roles for the current search", () => {
    expect(roleCounts(users, "")).toEqual({ all: 3, member: 1, athlete: 1, admin: 1 });
    expect(roleCounts(users, "ελενη")).toEqual({ all: 1, member: 0, athlete: 1, admin: 0 });
  });

  it("filters by role and finance status and sorts", () => {
    const base = { query: "", role: "all" as const, finance: "all", sort: "name" as const };
    expect(filterDirectory(users, base).map((entry) => entry.id)).toEqual(["3", "2", "1"]);
    expect(filterDirectory(users, { ...base, sort: "newest" }).map((entry) => entry.id)).toEqual(["2", "1", "3"]);
    expect(filterDirectory(users, { ...base, finance: "none" }).map((entry) => entry.id)).toEqual(["3", "2"]);
    expect(filterDirectory(users, { ...base, role: "athlete" }).map((entry) => entry.id)).toEqual(["1"]);
  });

  it("builds initials and stable avatar tones", () => {
    expect(initialsOf("maria_papadopoulou")).toBe("MP");
    expect(initialsOf("bob")).toBe("BO");
    expect(avatarTone("abc")).toBe(avatarTone("abc"));
    expect(avatarTone("abc")).toMatch(/^var\(--series-[1-8]\)$/);
  });
});

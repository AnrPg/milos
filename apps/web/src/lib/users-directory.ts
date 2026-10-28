import type { AdminUserDirectoryEntry } from "@/api/admin-users";
import { SERIES_TOKENS, tokenVar } from "@/lib/theme";

export type DirectoryRole = "all" | "member" | "athlete" | "staff";

/** Roles in privilege order (ADR-099); the list shows them in this order. */
const ROLE_ORDER = ["owner", "admin", "coach", "front_desk", "accountant", "janitor", "member", "athlete"];
const STAFF_ROLES = new Set(["owner", "admin", "coach", "front_desk", "accountant", "janitor"]);

/**
 * ADR-217: a person's roles in this box, never the account-wide role. Falls
 * back to the primary `role` when the API sent no role set.
 */
export function rolesOf(user: Pick<AdminUserDirectoryEntry, "role" | "roles">): string[] {
  const roles = user.roles?.length ? user.roles : [user.role];
  return ROLE_ORDER.filter((role) => roles.includes(role));
}

export function isStaff(user: Pick<AdminUserDirectoryEntry, "role" | "roles" | "staff">) {
  return user.staff ?? rolesOf(user).some((role) => STAFF_ROLES.has(role));
}

/**
 * The role words a person is shown with, in privilege order. A coach who sees
 * every client reads as head coach (`coach_scope: all`, ontology §4.3).
 */
export function displayRoles(user: Pick<AdminUserDirectoryEntry, "role" | "roles" | "coach_scope">): string[] {
  return rolesOf(user).map((role) => (role === "coach" && user.coach_scope === "all" ? "head_coach" : role));
}

function matchesRole(user: AdminUserDirectoryEntry, role: DirectoryRole) {
  if (role === "all") return true;
  if (role === "staff") return isStaff(user);
  return rolesOf(user).includes(role);
}
export type DirectorySort = "name" | "newest" | "oldest";
export type DirectoryFilters = { query: string; role: DirectoryRole; finance: string; sort: DirectorySort };

/** Case- and accent-insensitive match, e.g. "ελενη" finds "Ελένη". */
export function normalizeSearch(value: string) {
  return value.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLocaleLowerCase().trim();
}

function matchesQuery(user: AdminUserDirectoryEntry, query: string) {
  const needle = normalizeSearch(query);
  return !needle || normalizeSearch(user.nickname).includes(needle);
}

export function roleCounts(users: AdminUserDirectoryEntry[], query: string): Record<DirectoryRole, number> {
  const counts: Record<DirectoryRole, number> = { all: 0, member: 0, athlete: 0, staff: 0 };
  for (const user of users) {
    if (!matchesQuery(user, query)) continue;
    for (const role of ["all", "member", "athlete", "staff"] as const) {
      if (matchesRole(user, role)) counts[role] += 1;
    }
  }
  return counts;
}

export function filterDirectory(users: AdminUserDirectoryEntry[], filters: DirectoryFilters) {
  const filtered = users.filter(
    (user) =>
      matchesQuery(user, filters.query) &&
      matchesRole(user, filters.role) &&
      (filters.finance === "all" || (user.finance_status ?? "none") === filters.finance),
  );

  const joined = (user: AdminUserDirectoryEntry) => (user.joined_at ? Date.parse(user.joined_at) : 0);
  return filtered.sort((left, right) => {
    if (filters.sort === "newest") return joined(right) - joined(left);
    if (filters.sort === "oldest") return joined(left) - joined(right);
    return left.nickname.localeCompare(right.nickname, undefined, { sensitivity: "base" });
  });
}

export function initialsOf(name: string) {
  const parts = name.trim().split(/[\s._-]+/).filter(Boolean);
  const letters = parts.length > 1 ? `${parts[0]![0]}${parts[1]![0]}` : name.trim().slice(0, 2);
  return letters.toLocaleUpperCase();
}

/**
 * A stable theme series colour per user (one of `SERIES_TOKENS`), so avatars keep
 * their colour between visits and follow the theme (ADR-194: no computed
 * hsl()).
 */
export function avatarTone(id: string) {
  let hash = 0;
  for (const char of id) hash = (hash * 31 + char.charCodeAt(0)) % SERIES_TOKENS.length;
  return tokenVar(SERIES_TOKENS[hash]);
}

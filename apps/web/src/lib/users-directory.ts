import type { AdminUserDirectoryEntry } from "@/api/admin-users";

export type DirectoryRole = "all" | "member" | "athlete" | "admin";
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
  const counts: Record<DirectoryRole, number> = { all: 0, member: 0, athlete: 0, admin: 0 };
  for (const user of users) {
    if (!matchesQuery(user, query)) continue;
    counts.all += 1;
    counts[user.role] += 1;
  }
  return counts;
}

export function filterDirectory(users: AdminUserDirectoryEntry[], filters: DirectoryFilters) {
  const filtered = users.filter(
    (user) =>
      matchesQuery(user, filters.query) &&
      (filters.role === "all" || user.role === filters.role) &&
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

/** Stable hue per user so avatars keep their colour between visits. */
export function avatarHue(id: string) {
  let hash = 0;
  for (const char of id) hash = (hash * 31 + char.charCodeAt(0)) % 360;
  return hash;
}

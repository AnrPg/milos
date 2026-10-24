import type { VaultGroup } from "@/api/account-training";
import type { EntrySource } from "@/api/providers";
import { sourceToken } from "@/lib/provider-sources";

/**
 * Vault's folders (ANR 2026-10-24, «like the staff side»): the member's done
 * workouts filed by where they were done (box, coach, freeform, device),
 * then by workout type. A workout done in two places sits in both. With a
 * single source the source level is skipped, so there is no folder that
 * only holds one folder.
 */
export type VaultFolder = {
  /** Stable path id: `source:<token>`, `source:<token>/type:<type>` or `type:<type>`. */
  id: string;
  label: { kind: "source"; source: EntrySource } | { kind: "type"; type: string | null };
  folders: VaultFolder[];
  groups: VaultGroup[];
  /** Workouts in this folder and every folder under it. */
  count: number;
};

export type VaultViewMode = "folders" | "tree";
export const VAULT_VIEW_MODES: readonly VaultViewMode[] = ["folders", "tree"];

const OTHER = "\u0000other";

function byType(groups: VaultGroup[], parentId: string | null): VaultFolder[] {
  const buckets = new Map<string, VaultGroup[]>();
  for (const group of groups) {
    const key = group.workout_type?.trim() || OTHER;
    buckets.set(key, [...(buckets.get(key) ?? []), group]);
  }
  return [...buckets.entries()]
    .sort(([a], [b]) => (a === OTHER ? 1 : b === OTHER ? -1 : a.localeCompare(b)))
    .map(([key, items]) => {
      const type = key === OTHER ? null : key;
      const own = `type:${type ?? "other"}`;
      return {
        id: parentId ? `${parentId}/${own}` : own,
        label: { kind: "type", type },
        folders: [],
        groups: items,
        count: items.length,
      } satisfies VaultFolder;
    });
}

export function vaultFolders(groups: VaultGroup[]): VaultFolder[] {
  const sources = new Map<string, { source: EntrySource; groups: VaultGroup[] }>();
  for (const group of groups) {
    const seen = new Set<string>();
    for (const source of group.sources) {
      const token = sourceToken(source);
      if (seen.has(token)) continue;
      seen.add(token);
      const entry = sources.get(token) ?? { source, groups: [] };
      entry.groups.push(group);
      sources.set(token, entry);
    }
  }
  if (sources.size <= 1) return byType(groups, null);
  return [...sources.entries()]
    .sort(([, a], [, b]) => b.groups.length - a.groups.length)
    .map(([token, { source, groups: items }]) => {
      const id = `source:${token}`;
      return { id, label: { kind: "source", source }, folders: byType(items, id), groups: [], count: items.length };
    });
}

/** The folders along a path of ids, outermost first; stops at the first id that no longer exists. */
export function folderTrail(roots: VaultFolder[], path: string[]): VaultFolder[] {
  const trail: VaultFolder[] = [];
  let level = roots;
  for (const id of path) {
    const folder = level.find((candidate) => candidate.id === id);
    if (!folder) break;
    trail.push(folder);
    level = folder.folders;
  }
  return trail;
}

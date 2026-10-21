/**
 * Pure logic behind the anatomy figure (ADR-164), free of three.js so it can
 * be unit-tested and shipped in the main bundle: mesh-name parsing, the
 * highlight -> mesh role map, tap resolution (group, then head) and camera
 * focus bounds from the atlas index.
 */
import { MUSCLE_NODES, groupOf, leafForTa2, muscleNode, type MuscleNodeId } from "./taxonomy";

export const ANATOMY_ROLES = ["primary", "secondary", "stabilizer", "felt"] as const;
export type AnatomyRole = (typeof ANATOMY_ROLES)[number];
export type AnatomyHighlights = Partial<Record<MuscleNodeId, AnatomyRole>>;
export type AnatomyView = "front" | "back" | "both";
export type AnatomyPickLevel = "group" | "head";
export type AnatomyPick = { nodeId: MuscleNodeId; level: AnatomyPickLevel };

/** Where the vendored atlas lives (public/anatomy/v1, see ATTRIBUTION.md there). */
export const ATLAS_BASE_URL = "/anatomy/v1";

/**
 * Atlas nodes are named `ta2-<id>.<l|r|m>`. three.js sanitises node names on
 * load and drops the dot, so `ta2-2453.l` arrives as `ta2-2453l`.
 */
export function parseAtlasNodeName(name: string): { ta2: string; side: "l" | "r" | "m" | null } | null {
  const match = /^ta2-(\d+)(?:[._]?([lrm]))?$/.exec(name);
  if (!match) return null;
  return { ta2: match[1], side: (match[2] as "l" | "r" | "m" | undefined) ?? null };
}

// When a mesh is named by several highlights, the stronger role shows.
// What the member felt is their own report, so it wins over the plan.
const ROLE_RANK: Record<AnatomyRole, number> = { felt: 4, primary: 3, secondary: 2, stabilizer: 1 };

/** ta2 id -> role to paint. Unknown node ids are ignored; meshes not in the map render neutral. */
export function roleByTa2(highlights: AnatomyHighlights): Map<string, AnatomyRole> {
  const roles = new Map<string, AnatomyRole>();
  for (const [nodeId, role] of Object.entries(highlights)) {
    const node = muscleNode(nodeId);
    if (!node || !role || !(role in ROLE_RANK)) continue;
    for (const ta2 of node.ta2Ids) {
      const current = roles.get(ta2);
      if (!current || ROLE_RANK[role] > ROLE_RANK[current]) roles.set(ta2, role);
    }
  }
  return roles;
}

/** A stable key for a highlight set (memoising thumbnails). */
export function highlightsKey(highlights: AnatomyHighlights): string {
  return Object.entries(highlights)
    .filter(([nodeId, role]) => role && muscleNode(nodeId))
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([nodeId, role]) => `${nodeId}:${role}`)
    .join(",");
}

/** Highlighted node ids per role, in tree order (for the text alternative). */
export function highlightsByRole(highlights: AnatomyHighlights): Array<[AnatomyRole, MuscleNodeId[]]> {
  return ANATOMY_ROLES.map((role) => [role, MUSCLE_NODES.filter((node) => highlights[node.id] === role).map((node) => node.id)] as [AnatomyRole, MuscleNodeId[]]).filter(
    ([, ids]) => ids.length > 0,
  );
}

/**
 * A tap on a mesh picks its group; a second tap inside the same group picks
 * the head under the pointer. A group without heads stays a group pick.
 * Meshes outside the taxonomy pick nothing.
 */
export function resolvePick(ta2: string, previous: AnatomyPick | null): AnatomyPick | null {
  const leaf = leafForTa2(ta2);
  if (!leaf?.groupId) return null;
  const sameGroup = previous != null && groupOf(previous.nodeId) === leaf.groupId;
  if (sameGroup && leaf.kind === "head") return { nodeId: leaf.id, level: "head" };
  return { nodeId: leaf.groupId, level: "group" };
}

export type AtlasIndex = {
  nodes: Record<string, { c: [number, number, number]; r: number; box: [number, number, number, number, number, number] }>;
};

export type FocusBounds = {
  center: [number, number, number];
  size: [number, number, number];
  /** True when the node sits on the back of the body (the atlas faces +Z). */
  posterior: boolean;
};

const POSTERIOR_Z = -0.03;

/** The union of the boxes of every mesh (both sides) drawing a node, or null when none is known. */
export function focusBounds(nodeId: MuscleNodeId, index: AtlasIndex): FocusBounds | null {
  const node = muscleNode(nodeId);
  if (!node) return null;
  const wanted = new Set(node.ta2Ids);
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  let zSum = 0;
  let count = 0;
  for (const [name, entry] of Object.entries(index.nodes)) {
    const parsed = parseAtlasNodeName(name);
    if (!parsed || !wanted.has(parsed.ta2)) continue;
    for (let axis = 0; axis < 3; axis += 1) {
      min[axis] = Math.min(min[axis], entry.box[axis]);
      max[axis] = Math.max(max[axis], entry.box[axis + 3]);
    }
    zSum += entry.c[2];
    count += 1;
  }
  if (count === 0) return null;
  const center = [0, 1, 2].map((axis) => (min[axis] + max[axis]) / 2) as [number, number, number];
  const size = [0, 1, 2].map((axis) => max[axis] - min[axis]) as [number, number, number];
  return { center, size, posterior: zSum / count < POSTERIOR_Z };
}

export type AnatomyPalette = Record<AnatomyRole | "base" | "bone", string>;

/** Used before CSS is readable (tests, SSR) and when a token is missing. */
export const DEFAULT_ANATOMY_PALETTE: AnatomyPalette = {
  primary: "#D9743D",
  secondary: "#EFA36F",
  stabilizer: "#F3CDB0",
  felt: "#3FA37A",
  base: "#8E7A75",
  bone: "#E3DACB",
};

const PALETTE_TOKENS: Record<keyof AnatomyPalette, string> = {
  primary: "--anatomy-primary",
  secondary: "--anatomy-secondary",
  stabilizer: "--anatomy-stabilizer",
  felt: "--anatomy-felt",
  base: "--anatomy-base",
  bone: "--anatomy-bone",
};

/** Reads the role colours from the theme's CSS tokens so the figure follows the theme. */
export function readAnatomyPalette(element?: Element | null): AnatomyPalette {
  if (typeof window === "undefined") return DEFAULT_ANATOMY_PALETTE;
  const style = window.getComputedStyle(element ?? document.documentElement);
  const palette = { ...DEFAULT_ANATOMY_PALETTE };
  for (const [key, token] of Object.entries(PALETTE_TOKENS) as Array<[keyof AnatomyPalette, string]>) {
    const value = style.getPropertyValue(token).trim();
    if (value) palette[key] = value;
  }
  return palette;
}

export function paletteKey(palette: AnatomyPalette): string {
  return Object.keys(PALETTE_TOKENS)
    .map((key) => palette[key as keyof AnatomyPalette])
    .join("|");
}

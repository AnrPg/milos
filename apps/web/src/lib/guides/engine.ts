import type { GuideProgress } from "@/api/guides";

import type { Guide, GuideAbilities, GuideId, GuideRoute, GuideStep } from "./types";

/**
 * The walkthrough engine's pure parts (ADR-193): which steps a person
 * sees, where a step lives, and how a guide's stored progress reads on the
 * guides list and in the first-visit offer. The overlay and the provider
 * use these; nothing here touches the DOM.
 */

/** The steps this person sees, in order. */
export function visibleSteps(guide: Guide, abilities: GuideAbilities): GuideStep[] {
  return guide.steps.filter(
    (step) => (!step.requires || abilities[step.requires]) && (!step.unless || !abilities[step.unless]),
  );
}

/** A path without the `/org/<slug>` prefix every admin page may carry. */
export function stripOrganization(pathname: string) {
  return pathname.replace(/^\/org\/[^/]+(?=\/|$)/, "") || "/";
}

/** Whether the page shows `route`: the same path, and every query value the route names. */
export function onRoute(route: GuideRoute, pathname: string, search: URLSearchParams | string) {
  if (stripOrganization(pathname).replace(/\/$/, "") !== route.path.replace(/\/$/, "")) return false;
  const params = typeof search === "string" ? new URLSearchParams(search) : search;
  return Object.entries(route.query ?? {}).every(([key, value]) => params.get(key) === value);
}

/** A message key under `Guides`: `<guide>.<step>.<part>` (title, body, tip; or `chapters.<id>`). */
export function stepCopyKey(guide: GuideId, step: string, part: string) {
  return [guide, step, part].join(".");
}

/** Values for the `:name` placeholders of route paths. */
export type RouteParams = { gymClub?: string | null };

/** A route with its placeholders filled; null when one has no value. */
export function resolveRoute(route: GuideRoute, params: RouteParams): GuideRoute | null {
  let missing = false;
  const path = route.path.replace(/:(\w+)/g, (_match, name: string) => {
    const value = params[name as keyof RouteParams];
    if (!value) missing = true;
    return encodeURIComponent(value ?? "");
  });
  return missing ? null : { ...route, path };
}

/** The link to `route`; admin pages go under the selected business. */
export function routeHref(route: GuideRoute, organizationSlug: string | null) {
  const query = new URLSearchParams(route.query ?? {}).toString();
  const path = route.admin && organizationSlug ? `/org/${organizationSlug}${route.path}` : route.path;
  return query ? `${path}?${query}` : path;
}

export type GuideState = "new" | "started" | "completed" | "dismissed" | "outdated";

/** How a guide reads for this person; a finished older version counts as outdated. */
export function guideState(guide: Guide, progress: GuideProgress | null | undefined): GuideState {
  if (!progress) return "new";
  if (progress.version < guide.version) return progress.status === "started" ? "new" : "outdated";
  return progress.status;
}

/**
 * Where a run resumes: the unfinished step of this version, moved back to
 * the nearest step that can open on its own (one with its own route, or the
 * start), since a step inside an editor needs the step that opened it.
 */
export function resumeIndex(guide: Guide, progress: GuideProgress | null | undefined, steps: GuideStep[]) {
  if (!progress || progress.status !== "started" || progress.version < guide.version) return 0;
  let index = Math.min(Math.max(progress.step, 0), Math.max(steps.length - 1, 0));
  while (index > 0 && !steps[index]?.route) index -= 1;
  return index;
}

/** The page a run starts on: the step's own route, else the guide's home. */
export function startRoute(guide: Guide, steps: GuideStep[], index: number): GuideRoute {
  return steps[index]?.route ?? guide.home;
}

/**
 * The first-visit offer: on the guide's home, for a guide never opened, or
 * finished in an older version (it changed since). A «not now» is final;
 * the guides list still has it.
 */
export function shouldOffer(guide: Guide, progress: GuideProgress | null | undefined, pathname: string, search: string) {
  const state = guideState(guide, progress);
  const fresh = state === "new" || (state === "outdated" && progress?.status === "completed");
  return fresh && onRoute(guide.home, pathname, search);
}

/** The guides a person may open, staff guides first. */
export function availableGuides(guides: readonly Guide[], abilities: GuideAbilities) {
  return guides
    .filter((guide) => guide.requires(abilities))
    .sort((a, b) => (a.audience === b.audience ? 0 : a.audience === "staff" ? -1 : 1));
}

export function progressFor(rows: readonly GuideProgress[] | undefined, id: GuideId) {
  return rows?.find((row) => row.guide_id === id) ?? null;
}

/** The active run kept for this tab, so a guide survives navigation and a reload. */
export type GuideRun = { guide: GuideId; index: number };

const RUN_KEY = "palee-guide-run";

export function readRun(isGuide: (id: string) => id is GuideId): GuideRun | null {
  try {
    const raw = window.sessionStorage.getItem(RUN_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<GuideRun>;
    if (typeof parsed.guide !== "string" || !isGuide(parsed.guide) || typeof parsed.index !== "number") return null;
    return { guide: parsed.guide, index: Math.max(0, Math.floor(parsed.index)) };
  } catch {
    return null;
  }
}

export function writeRun(run: GuideRun | null) {
  try {
    if (run) window.sessionStorage.setItem(RUN_KEY, JSON.stringify(run));
    else window.sessionStorage.removeItem(RUN_KEY);
  } catch {
    // Private mode: the run lasts until the next reload.
  }
}

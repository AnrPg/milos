/**
 * Pure state logic behind the WOD goals screens (ADR-163): the coach panel's
 * suggested-vs-edited state, role cycling, highlights for the figure, the
 * short «Στόχοι: …» summary and «Τι ένιωσες;» selections.
 */
import type { AnatomyHighlights } from "@/lib/anatomy/figure";
import { groupOf, muscleNode, MUSCLE_NODES, type MuscleNodeId } from "@/lib/anatomy/taxonomy";
import type { GoalMuscle, GoalRole, SaveWorkoutGoalsRequest, StaffWorkoutGoalsResponse } from "@/api/wod-goals";

export const STIMULUS_MAX_LENGTH = 280;

const ROLE_ORDER: readonly GoalRole[] = ["primary", "secondary", "stabilizer"];

/** primary → secondary → stabilizer → off (null). */
export function nextRole(role: GoalRole | null | undefined): GoalRole | null {
  if (!role) return "primary";
  const index = ROLE_ORDER.indexOf(role);
  return index < 0 || index === ROLE_ORDER.length - 1 ? null : ROLE_ORDER[index + 1];
}

/** Sets a muscle's role (null removes it), keeping the list's order for existing muscles. */
export function setMuscleRole(muscles: readonly GoalMuscle[], id: MuscleNodeId, role: GoalRole | null): GoalMuscle[] {
  const existing = muscles.some((muscle) => muscle.id === id);
  if (role === null) return muscles.filter((muscle) => muscle.id !== id);
  if (existing) return muscles.map((muscle) => (muscle.id === id ? { id, role } : muscle));
  return [...muscles, { id, role }];
}

export function cycleMuscleRole(muscles: readonly GoalMuscle[], id: MuscleNodeId): GoalMuscle[] {
  const current = muscles.find((muscle) => muscle.id === id)?.role;
  return setMuscleRole(muscles, id, nextRole(current));
}

export function toggleValue<T>(values: readonly T[], value: T): T[] {
  return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
}

/** Muscles grouped by role, in role order; empty roles are omitted. */
export function musclesByRole(muscles: readonly GoalMuscle[]): Array<[GoalRole, GoalMuscle[]]> {
  return ROLE_ORDER.map((role) => [role, muscles.filter((muscle) => muscle.role === role)] as [GoalRole, GoalMuscle[]]).filter(
    ([, list]) => list.length > 0,
  );
}

/** Figure highlights from goal muscles; `roles` limits which roles are drawn (cards hide stabilizers). */
export function goalHighlights(muscles: readonly GoalMuscle[], roles: readonly GoalRole[] = ROLE_ORDER): AnatomyHighlights {
  const highlights: AnatomyHighlights = {};
  for (const muscle of muscles) if (roles.includes(muscle.role) && muscleNode(muscle.id)) highlights[muscle.id] = muscle.role;
  return highlights;
}

/** Goals in their role colour with what the member felt drawn over them. */
export function feltHighlights(goals: readonly GoalMuscle[], felt: readonly MuscleNodeId[]): AnatomyHighlights {
  const highlights = goalHighlights(goals);
  for (const id of felt) if (muscleNode(id)) highlights[id] = "felt";
  return highlights;
}

/**
 * Up to `limit` node ids naming the primary muscles for a one-line summary:
 * a head is named by its group, duplicates dropped, in the coach's order.
 */
export function summaryMuscleIds(muscles: readonly GoalMuscle[], limit = 3): MuscleNodeId[] {
  const ids: MuscleNodeId[] = [];
  for (const muscle of muscles) {
    if (muscle.role !== "primary") continue;
    const id = groupOf(muscle.id) ?? muscle.id;
    if (!muscleNode(id) || ids.includes(id)) continue;
    ids.push(id);
    if (ids.length === limit) break;
  }
  return ids;
}

const sameMuscles = (a: readonly GoalMuscle[], b: readonly GoalMuscle[]) =>
  a.length === b.length && a.every((muscle) => b.some((other) => other.id === muscle.id && other.role === muscle.role));
const sameSet = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every((value) => b.includes(value));

// ── Coach panel state ─────────────────────────────────────────────────────────

export type GoalDraft = {
  muscles: GoalMuscle[];
  qualities: string[];
  stimulus: string;
  visible: boolean;
};

export type GoalSuggestionTarget = {
  muscles: GoalMuscle[];
  qualities: string[];
  matched: number;
  unmatched: number;
};

export type GoalPanelState = {
  loaded: boolean;
  draft: GoalDraft;
  suggestion: GoalSuggestionTarget | null;
  /** Whether anything is stored server side. */
  saved: boolean;
  /** The base workout these goals come from, until this workout saves its own. */
  inheritedFrom: string | null;
  /** Muscles and qualities track the suggestion until the coach edits them. */
  following: boolean;
  /** Bumped on every change that should be saved; compared with savedRevision. */
  revision: number;
  savedRevision: number;
};

export type GoalPanelAction =
  | { type: "loaded"; response: StaffWorkoutGoalsResponse }
  | { type: "setRole"; id: MuscleNodeId; role: GoalRole | null }
  | { type: "cycleRole"; id: MuscleNodeId }
  | { type: "setMuscles"; muscles: GoalMuscle[] }
  | { type: "toggleQuality"; quality: string }
  | { type: "setStimulus"; stimulus: string }
  | { type: "setVisible"; visible: boolean }
  | { type: "resetToSuggestion" }
  | { type: "savedRevision"; revision: number };

export const initialGoalPanelState: GoalPanelState = {
  loaded: false,
  draft: { muscles: [], qualities: [], stimulus: "", visible: false },
  suggestion: null,
  saved: false,
  inheritedFrom: null,
  following: true,
  revision: 0,
  savedRevision: 0,
};

function edit(state: GoalPanelState, draft: Partial<GoalDraft>, following = state.following): GoalPanelState {
  return { ...state, draft: { ...state.draft, ...draft }, following, revision: state.revision + 1 };
}

export function goalPanelReducer(state: GoalPanelState, action: GoalPanelAction): GoalPanelState {
  switch (action.type) {
    case "loaded": {
      const { goals, suggestion } = action.response;
      const target: GoalSuggestionTarget = {
        muscles: suggestion.muscles,
        qualities: suggestion.qualities,
        matched: suggestion.matched_exercises,
        unmatched: suggestion.unmatched_exercises,
      };
      if (!state.loaded) {
        // Inherited goals are the base workout's choice: they never follow the suggestion.
        const inheritedFrom = goals.saved ? null : goals.inherited_from ?? null;
        const following = !inheritedFrom && (!goals.saved || goals.source === "suggested");
        const loaded: GoalPanelState = {
          ...state,
          loaded: true,
          saved: goals.saved,
          inheritedFrom,
          following,
          suggestion: target,
          draft: { muscles: goals.muscles, qualities: goals.qualities, stimulus: goals.stimulus ?? "", visible: goals.visible_to_members },
        };
        return following && goals.saved ? follow(loaded, target) : loaded;
      }
      // Later reads (after a draft autosave or a save) refresh the suggestion.
      // Stored goals replace the local ones only while nothing local is
      // waiting to be saved; otherwise the coach's edits stay.
      if (goals.saved && !hasUnsavedChanges(state)) {
        const following = goals.source === "suggested" && state.following;
        const adopted: GoalPanelState = {
          ...state,
          saved: true,
          inheritedFrom: null,
          following,
          suggestion: target,
          draft: { muscles: goals.muscles, qualities: goals.qualities, stimulus: goals.stimulus ?? "", visible: goals.visible_to_members },
        };
        return following ? follow(adopted, target) : adopted;
      }
      const next = { ...state, suggestion: target, saved: state.saved || goals.saved };
      return state.following ? follow(next, target) : next;
    }
    case "setRole":
      return edit(state, { muscles: setMuscleRole(state.draft.muscles, action.id, action.role) }, false);
    case "cycleRole":
      return edit(state, { muscles: cycleMuscleRole(state.draft.muscles, action.id) }, false);
    case "setMuscles":
      return edit(state, { muscles: action.muscles }, false);
    case "toggleQuality":
      return edit(state, { qualities: toggleValue(state.draft.qualities, action.quality) }, false);
    case "setStimulus":
      return edit(state, { stimulus: action.stimulus.slice(0, STIMULUS_MAX_LENGTH) });
    case "setVisible":
      return edit(state, { visible: action.visible });
    case "resetToSuggestion":
      if (!state.suggestion) return state;
      return edit(state, { muscles: state.suggestion.muscles, qualities: state.suggestion.qualities }, true);
    case "savedRevision":
      return { ...state, saved: true, inheritedFrom: null, savedRevision: Math.max(state.savedRevision, action.revision) };
  }
}

// While following, a changed suggestion replaces the goals; when goals are
// already stored it is a change to save (members may see them).
function follow(state: GoalPanelState, target: GoalSuggestionTarget): GoalPanelState {
  if (sameMuscles(state.draft.muscles, target.muscles) && sameSet(state.draft.qualities, target.qualities)) return state;
  const draft = { ...state.draft, muscles: target.muscles, qualities: target.qualities };
  return state.saved ? { ...state, draft, revision: state.revision + 1 } : { ...state, draft };
}

export function hasUnsavedChanges(state: GoalPanelState) {
  return state.revision > state.savedRevision;
}

/** True when the goals differ from the reset target (offers «Επαναφορά πρότασης»). */
export function differsFromSuggestion(state: GoalPanelState) {
  if (!state.suggestion) return false;
  return !sameMuscles(state.draft.muscles, state.suggestion.muscles) || !sameSet(state.draft.qualities, state.suggestion.qualities);
}

export function savePayload(draft: GoalDraft): SaveWorkoutGoalsRequest {
  return {
    muscles: draft.muscles,
    qualities: draft.qualities,
    stimulus: draft.stimulus.trim() || null,
    visible_to_members: draft.visible,
  };
}

// ── Stimulus phrases ─────────────────────────────────────────────────────────

/** «12′» from a timer length in seconds; null when unknown. */
export function timeDomainLabel(seconds: number | null | undefined): string | null {
  if (!seconds || seconds <= 0) return null;
  return `${Math.max(1, Math.round(seconds / 60))}′`;
}

/** Appends a phrase to the stimulus text with a comma, within the length limit. */
export function insertPhrase(text: string, phrase: string): string {
  const trimmed = text.trimEnd();
  const next = trimmed ? `${trimmed.replace(/[,\s]+$/, "")}, ${phrase}` : phrase;
  return next.slice(0, STIMULUS_MAX_LENGTH);
}

// ── Picker list ──────────────────────────────────────────────────────────────

/** Regions with their groups and heads, filtered by a search over translated names. */
export function searchMuscleTree(match: (id: MuscleNodeId) => boolean) {
  const regions = MUSCLE_NODES.filter((node) => node.kind === "region");
  return regions
    .map((region) => {
      const regionMatches = match(region.id);
      const rows = MUSCLE_NODES.filter((node) => node.kind !== "region" && node.regionId === region.id).filter((node) => {
        if (regionMatches || match(node.id)) return true;
        // A group stays when one of its heads matches.
        return node.kind === "group" && MUSCLE_NODES.some((head) => head.groupId === node.id && head.kind === "head" && match(head.id));
      });
      return { region: region.id, rows: rows.map((node) => ({ id: node.id, kind: node.kind as "group" | "head" })) };
    })
    .filter((entry) => entry.rows.length > 0);
}

/** Lower-cased, accent-free text for search ("Τετρακέφαλος" matches "τετρακεφ"). */
export function searchKey(text: string) {
  return text
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase();
}

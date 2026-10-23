import type { EventScope } from "@/api/events";
import { formAudience, formProblems, type EventForm, type EventHostMode, type FormProblem } from "@/components/events/events";

/**
 * The event wizard (create and edit an event, one decision per screen):
 * which steps a host sees, what each step still needs, and the state the
 * shell moves through. Pure: no React, no storage, no clock of its own.
 *
 * 1. host     «Διοργάνωση ως» (ADR-185) and the club
 * 2. basics   title, cover, description
 * 3. when     date, time, zone (ADR-176/179), duration, weekly repeat
 * 4. where    a branch, or another address
 * 5. who      audience, free or paid, guest passes, good for friends
 * 6. capacity places, and co-hosts invited as it is published
 * 7. review   a summary that jumps back to any step
 */
export const EVENT_WIZARD_STEPS = ["host", "basics", "when", "where", "who", "capacity", "review"] as const;
export type EventWizardStep = (typeof EVENT_WIZARD_STEPS)[number];

/** The ADR-185 co-host limit (CohostPolicy.max_cohosts). */
export const MAX_COHOSTS = 10;

/** What the wizard knows about who is making the event and where. */
export type EventWizardContext = {
  mode: EventHostMode;
  editing: boolean;
  /** How many hosts («Ως εγώ» and businesses) the person can pick from. */
  hostChoices: number;
  /** How many clubs the chosen host can put the event in. */
  clubChoices: number;
  /** Co-hosts can be invited as the event is published (the caller can send the invites). */
  cohostsAtCreate: boolean;
  /** ADR-179: the gym's zone, the clock of an event without its own; null while unknown. */
  gymTimeZone: string | null;
  /** The box's location ids once known, else null (still loading, or none to check against). */
  locationIds: string[] | null;
};

export type WizardProblem = FormProblem;

/** Which step fixes each problem. */
export const PROBLEM_STEP: Record<WizardProblem, EventWizardStep> = {
  title: "basics",
  when: "when",
  past: "when",
  repeat: "when",
  place: "where",
  price: "who",
  capacity: "capacity",
};

/** The step that edits a field, for «Edit» links and for opening the editor on one field. */
export type EventWizardField = keyof EventForm | "host" | "club" | "cohosts";
const FIELD_STEP: Record<EventWizardField, EventWizardStep> = {
  host: "host",
  club: "host",
  title: "basics",
  coverMediaId: "basics",
  description: "basics",
  date: "when",
  time: "when",
  timeZone: "when",
  durationMinutes: "when",
  repeatWeekly: "when",
  repeatUntil: "when",
  place: "where",
  openToAll: "who",
  groupOnly: "who",
  paid: "who",
  price: "who",
  guestPass: "who",
  guestsPerMember: "who",
  goodForFriends: "who",
  capacity: "capacity",
  cohosts: "capacity",
};

export function stepForField(field: EventWizardField): EventWizardStep {
  return FIELD_STEP[field];
}

/**
 * The steps this host sees, in order. The host step only when there is a
 * choice to make (and never while editing: an event keeps its host);
 * everything else always, since each holds something every event needs.
 */
export function activeSteps(context: EventWizardContext): EventWizardStep[] {
  const needsHost = !context.editing && (context.hostChoices > 1 || context.clubChoices > 1);
  return EVENT_WIZARD_STEPS.filter((step) => step !== "host" || needsHost);
}

/** The form on the clock its date and time are read on: its own zone, else the gym's. */
export function clockForm(form: EventForm, context: Pick<EventWizardContext, "gymTimeZone">): EventForm {
  return { ...form, timeZone: form.timeZone ?? context.gymTimeZone };
}

/** Whether the guest pass question applies: a business's or club's event that is not for a group only. */
export function asksGuestPass(form: EventForm, mode: EventHostMode): boolean {
  return mode !== "self" && formAudience(form, mode) !== "group";
}

/** «Καλό για φίλους» (ADR-156) only where a friend can come: open to everyone, or with a guest pass. */
export function asksGoodForFriends(form: EventForm, mode: EventHostMode): boolean {
  return formAudience(form, mode) === "open" || (asksGuestPass(form, mode) && form.guestPass);
}

/** Co-hosts can be asked: the caller can send invites and the event is not for a group only (CohostPolicy). */
export function asksCohosts(form: EventForm, context: Pick<EventWizardContext, "cohostsAtCreate" | "editing" | "mode">): boolean {
  return context.cohostsAtCreate && !context.editing && context.mode !== "self" && formAudience(form, context.mode) !== "group";
}

/** Every problem of the whole form, on its clock, plus a branch that is no longer the box's. */
export function wizardProblems(form: EventForm, context: EventWizardContext, now: Date): WizardProblem[] {
  const problems = formProblems(clockForm(form, context), now, { editing: context.editing });
  const unknownPlace =
    !context.editing &&
    form.place.kind === "location" &&
    Boolean(form.place.locationId) &&
    context.locationIds !== null &&
    context.locationIds.length > 0 &&
    !context.locationIds.includes(form.place.locationId);
  if (unknownPlace && !problems.includes("place")) problems.push("place");
  return problems;
}

/** What a step still needs before Next; the review step needs everything. */
export function stepProblems(step: EventWizardStep, form: EventForm, context: EventWizardContext, now: Date): WizardProblem[] {
  const problems = wizardProblems(form, context, now);
  return step === "review" ? problems : problems.filter((problem) => PROBLEM_STEP[problem] === step);
}

/** The first step (in this host's order) with something to fix, or null when the form can be sent. */
export function firstInvalidStep(form: EventForm, context: EventWizardContext, now: Date): EventWizardStep | null {
  const problems = wizardProblems(form, context, now);
  return activeSteps(context).find((step) => step !== "review" && problems.some((problem) => PROBLEM_STEP[problem] === step)) ?? null;
}

// ------------------------------------------------------------------ co-hosts

/**
 * A business page address as the person pasted it («box-kypseli»,
 * «/b/box-kypseli», «https://palee.app/b/box-kypseli/») → «box-kypseli»;
 * null when it cannot be one. The API resolves it (EventCohosts).
 */
export function normalizeCohostSlug(raw: string): string | null {
  let value = raw.trim();
  if (!value) return null;
  value = value.replace(/^[a-z][a-z0-9+.-]*:\/\/[^/]+/i, "");
  value = value.replace(/[?#].*$/, "").replace(/^\/+|\/+$/g, "");
  value = value.replace(/^b\//i, "");
  value = value.toLowerCase();
  return /^[a-z0-9](?:[a-z0-9_-]{0,78}[a-z0-9])?$/.test(value) ? value : null;
}

export type CohostInputProblem = "cohost_format" | "cohost_duplicate" | "cohost_limit" | "cohost_self";

/** Why this address cannot be added to the list, or null. `ownSlug` is the host's own page. */
export function cohostInputProblem(raw: string, cohosts: string[], ownSlug: string | null = null): CohostInputProblem | null {
  const slug = normalizeCohostSlug(raw);
  if (!slug) return "cohost_format";
  if (ownSlug && slug === ownSlug.toLowerCase()) return "cohost_self";
  if (cohosts.includes(slug)) return "cohost_duplicate";
  if (cohosts.length >= MAX_COHOSTS) return "cohost_limit";
  return null;
}

// ------------------------------------------------------------------ state

export type EventWizardState = {
  form: EventForm;
  step: EventWizardStep;
  /** Steps the person has reached; the step bar lets them tap back to these. */
  visited: EventWizardStep[];
  /** They came from the review's «Edit»: Next goes straight back to it. */
  returnToReview: boolean;
  /** Business page addresses to invite as co-hosts once the event is published. */
  cohosts: string[];
  /** A weekly event's edit: this one, or this and the following. */
  scope: EventScope;
  /** They chose a place or audience themselves, so a late default never overrides it. */
  placeTouched: boolean;
  audienceTouched: boolean;
};

export type EventWizardAction =
  | { type: "set"; patch: Partial<EventForm> }
  | { type: "goto"; step: EventWizardStep; context: EventWizardContext }
  | { type: "next"; context: EventWizardContext; now: Date }
  | { type: "back"; context: EventWizardContext }
  | { type: "modeChanged"; mode: EventHostMode }
  | { type: "locationsArrived"; locationIds: string[]; editing: boolean }
  | { type: "addCohost"; raw: string; ownSlug?: string | null }
  | { type: "removeCohost"; slug: string }
  | { type: "scope"; scope: EventScope }
  | { type: "restore"; draft: EventWizardDraft; context: EventWizardContext };

/** Where the wizard opens: the first step to create; the review (or the field's step) to edit. */
export function initialWizardState(
  form: EventForm,
  context: EventWizardContext,
  { startStep = null, cohosts = [] }: { startStep?: EventWizardStep | null; cohosts?: string[] } = {},
): EventWizardState {
  const steps = activeSteps(context);
  const fallback = context.editing ? "review" : steps[0];
  const step = startStep && steps.includes(startStep) ? startStep : fallback;
  return {
    form,
    step,
    visited: context.editing ? steps : steps.slice(0, steps.indexOf(step) + 1),
    returnToReview: context.editing && step !== "review",
    cohosts,
    scope: "this",
    placeTouched: false,
    audienceTouched: false,
  };
}

/** Whether the step bar lets them jump to this step now. */
export function canVisit(state: EventWizardState, step: EventWizardStep, context: EventWizardContext): boolean {
  return activeSteps(context).includes(step) && (context.editing || state.visited.includes(step));
}

/** The step after this one (the review when they came from it), or null on the review. */
export function nextStep(state: EventWizardState, context: EventWizardContext): EventWizardStep | null {
  const steps = activeSteps(context);
  if (state.step === "review") return null;
  if (state.returnToReview) return "review";
  const index = steps.indexOf(state.step);
  return steps[index + 1] ?? "review";
}

/** The step before this one, or null on the first. */
export function previousStep(state: EventWizardState, context: EventWizardContext): EventWizardStep | null {
  const steps = activeSteps(context);
  const index = steps.indexOf(state.step);
  return index > 0 ? steps[index - 1] : null;
}

/** The step to be on once the active steps change (a step can drop away under them). */
function settle(state: EventWizardState, context: EventWizardContext): EventWizardState {
  const steps = activeSteps(context);
  if (steps.includes(state.step)) return state;
  const index = EVENT_WIZARD_STEPS.indexOf(state.step);
  const step = steps.find((candidate) => EVENT_WIZARD_STEPS.indexOf(candidate) > index) ?? steps[steps.length - 1];
  return { ...state, step, visited: state.visited.includes(step) ? state.visited : [...state.visited, step] };
}

function visit(state: EventWizardState, step: EventWizardStep): EventWizardState {
  return { ...state, step, visited: state.visited.includes(step) ? state.visited : [...state.visited, step] };
}

export function eventWizardReducer(state: EventWizardState, action: EventWizardAction): EventWizardState {
  switch (action.type) {
    case "set": {
      const placeTouched = state.placeTouched || "place" in action.patch;
      const audienceTouched = state.audienceTouched || "openToAll" in action.patch || "groupOnly" in action.patch;
      return { ...state, form: { ...state.form, ...action.patch }, placeTouched, audienceTouched };
    }
    case "goto": {
      const current = settle(state, action.context);
      if (action.step === current.step || !canVisit(current, action.step, action.context)) return current;
      const returnToReview = action.step === "review" ? false : current.step === "review" || current.returnToReview;
      return { ...visit(current, action.step), returnToReview };
    }
    case "next": {
      const current = settle(state, action.context);
      if (stepProblems(current.step, current.form, action.context, action.now).length > 0) return current;
      const step = nextStep(current, action.context);
      if (!step) return current;
      return { ...visit(current, step), returnToReview: step === "review" ? false : current.returnToReview };
    }
    case "back": {
      const current = settle(state, action.context);
      const step = previousStep(current, action.context);
      return step ? { ...current, step, returnToReview: false } : current;
    }
    case "modeChanged": {
      // A new host sets the audience's default («Ως εγώ» is for everyone)
      // until they pick one themselves.
      if (state.audienceTouched) return state;
      return { ...state, form: { ...state.form, openToAll: action.mode === "self", groupOnly: true } };
    }
    case "locationsArrived": {
      const [first] = action.locationIds;
      if (!first || state.placeTouched || action.editing) return state;
      const place = state.form.place;
      const blankAddress = place.kind === "address" && !place.name.trim() && !place.address.trim();
      const goneLocation = place.kind === "location" && !action.locationIds.includes(place.locationId);
      if (!blankAddress && !goneLocation) return state;
      return { ...state, form: { ...state.form, place: { kind: "location", locationId: first } } };
    }
    case "addCohost": {
      if (cohostInputProblem(action.raw, state.cohosts, action.ownSlug ?? null)) return state;
      return { ...state, cohosts: [...state.cohosts, normalizeCohostSlug(action.raw)!] };
    }
    case "removeCohost":
      return { ...state, cohosts: state.cohosts.filter((slug) => slug !== action.slug) };
    case "scope":
      return { ...state, scope: action.scope };
    case "restore": {
      const steps = activeSteps(action.context);
      const visited = action.draft.visited.filter((step) => steps.includes(step));
      const step = steps.includes(action.draft.step) ? action.draft.step : steps[0];
      return {
        ...state,
        form: action.draft.form,
        cohosts: action.draft.cohosts,
        step,
        visited: visited.includes(step) ? visited : [...visited, step],
        returnToReview: false,
        placeTouched: true,
        audienceTouched: true,
      };
    }
  }
}

// ------------------------------------------------------------------ drafts

/**
 * A new event's draft, kept on this device per host so closing the wizard
 * loses nothing. Never sent anywhere; an edit keeps none.
 */
export type EventWizardDraft = {
  version: typeof EVENT_WIZARD_DRAFT_VERSION;
  savedAt: string;
  form: EventForm;
  step: EventWizardStep;
  visited: EventWizardStep[];
  cohosts: string[];
};

export const EVENT_WIZARD_DRAFT_VERSION = 1;
/** A draft older than this is dropped rather than offered. */
export const EVENT_WIZARD_DRAFT_MAX_AGE_MS = 14 * 24 * 60 * 60 * 1000;

export function eventWizardDraftKey(hostKey: string): string {
  return ["palee", "event-wizard-draft", `v${EVENT_WIZARD_DRAFT_VERSION}`, hostKey].join(":");
}

export function draftFromState(state: EventWizardState, now: Date): EventWizardDraft {
  return {
    version: EVENT_WIZARD_DRAFT_VERSION,
    savedAt: now.toISOString(),
    form: state.form,
    step: state.step,
    visited: state.visited,
    cohosts: state.cohosts,
  };
}

/** Whether there is anything worth keeping: the person changed something from the blank form. */
export function draftWorthKeeping(state: EventWizardState, blank: EventForm): boolean {
  if (state.cohosts.length > 0) return true;
  // The place counts only once they chose it: a default branch arriving late is not theirs.
  const rest = ({ place: _place, ...form }: EventForm) => JSON.stringify(form);
  if (state.placeTouched && JSON.stringify(state.form.place) !== JSON.stringify(blank.place)) return true;
  return rest(state.form) !== rest(blank);
}

const isString = (value: unknown): value is string => typeof value === "string";
const isBoolean = (value: unknown): value is boolean => typeof value === "boolean";
const isStep = (value: unknown): value is EventWizardStep => (EVENT_WIZARD_STEPS as readonly unknown[]).includes(value);

function parseForm(value: unknown): EventForm | null {
  if (!value || typeof value !== "object") return null;
  const form = value as Record<string, unknown>;
  const place = form.place as Record<string, unknown> | undefined;
  const placeOk =
    place && typeof place === "object"
      ? (place.kind === "location" && isString(place.locationId)) || (place.kind === "address" && isString(place.name) && isString(place.address))
      : false;
  const ok =
    placeOk &&
    ["title", "description", "date", "time", "capacity", "price", "repeatUntil"].every((key) => isString(form[key])) &&
    ["paid", "openToAll", "guestPass", "goodForFriends", "repeatWeekly"].every((key) => isBoolean(form[key])) &&
    typeof form.durationMinutes === "number" &&
    form.durationMinutes > 0 &&
    typeof form.guestsPerMember === "number" &&
    (form.coverMediaId === null || isString(form.coverMediaId)) &&
    (form.timeZone === null || isString(form.timeZone)) &&
    (form.groupOnly === undefined || isBoolean(form.groupOnly));
  return ok ? (value as EventForm) : null;
}

/** A stored draft, or null when it is missing, from another version, malformed or too old. */
export function parseEventWizardDraft(raw: string | null, now: Date, maxAgeMs = EVENT_WIZARD_DRAFT_MAX_AGE_MS): EventWizardDraft | null {
  if (!raw) return null;
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!value || typeof value !== "object") return null;
  const draft = value as Record<string, unknown>;
  if (draft.version !== EVENT_WIZARD_DRAFT_VERSION || !isString(draft.savedAt)) return null;
  const savedAt = new Date(draft.savedAt).getTime();
  if (Number.isNaN(savedAt) || now.getTime() - savedAt > maxAgeMs) return null;
  const form = parseForm(draft.form);
  if (!form || !isStep(draft.step) || !Array.isArray(draft.visited) || !Array.isArray(draft.cohosts)) return null;
  return {
    version: EVENT_WIZARD_DRAFT_VERSION,
    savedAt: draft.savedAt,
    form,
    step: draft.step,
    visited: draft.visited.filter(isStep),
    cohosts: draft.cohosts.filter(isString).map(normalizeCohostSlug).filter((slug): slug is string => Boolean(slug)).slice(0, MAX_COHOSTS),
  };
}

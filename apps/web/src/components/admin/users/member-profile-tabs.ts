import type { CoachNote, CoachNoteSubjectKind } from "@/api/roles";

/**
 * ADR-140 §8: the staff member profile has six tabs, a few sections each;
 * ADR-158 adds «Σώμα» for a client's coach (snapshots the member shared).
 * The active tab is in the URL (`?tab=`), so a link opens the right one.
 */
export const PROFILE_TABS = ["overview", "training", "wellbeing", "body", "coaching", "finance", "account"] as const;
export type ProfileTab = (typeof PROFILE_TABS)[number];

/** Which tab holds each section (the `#section` anchors keep working). */
export const SECTION_TAB: Record<string, ProfileTab> = {
  overview: "overview",
  box_message: "overview",
  schedule: "training",
  // ADR-221: the client's own weekly goal, which their coach may set.
  training_goal: "training",
  training_history: "training",
  // ADR-165: the client's coverage, qualities and load (shared entries only).
  training_depth: "training",
  prs: "training",
  training_notes: "training",
  health_incidents: "wellbeing",
  wellbeing_notes: "wellbeing",
  // ADR-160: the weekly wellness summary the member chose to share.
  wellness_summary: "wellbeing",
  body: "body",
  coaching_context: "coaching",
  coaching_relationships: "coaching",
  coach_notes: "coaching",
  messages: "coaching",
  finance: "finance",
  admin_actions: "account",
};

/** ADR-140 §5: a note about one thing shows in that thing's tab too. */
export const SUBJECT_TAB: Record<CoachNoteSubjectKind, ProfileTab> = {
  execution: "training",
  training_log: "training",
  pr: "training",
  assignment: "training",
  injury: "wellbeing",
  form_review: "coaching",
};

export function subjectKindsFor(tab: ProfileTab): CoachNoteSubjectKind[] {
  return (Object.keys(SUBJECT_TAB) as CoachNoteSubjectKind[]).filter((kind) => SUBJECT_TAB[kind] === tab);
}

/** Notes whose subject belongs to the given kinds (no kinds: every note). */
export function notesAbout<T extends Pick<CoachNote, "subject_kind">>(notes: T[], kinds?: CoachNoteSubjectKind[]): T[] {
  if (!kinds) return notes;
  return notes.filter((note) => note.subject_kind != null && kinds.includes(note.subject_kind));
}

/** Tabs with something in them for this viewer, in order. */
export function visibleProfileTabs(sections: Iterable<string>): ProfileTab[] {
  const present = new Set<ProfileTab>(["overview"]);
  for (const section of sections) {
    const tab = SECTION_TAB[section];
    if (tab) present.add(tab);
  }
  return PROFILE_TABS.filter((tab) => present.has(tab));
}

/** The tab to show: the URL's when it is visible, else the section's, else Επισκόπηση. */
export function activeProfileTab(visible: ProfileTab[], requested: string | null, hashSection?: string | null): ProfileTab {
  if (requested && (visible as string[]).includes(requested)) return requested as ProfileTab;
  const fromHash = hashSection ? SECTION_TAB[hashSection] : undefined;
  if (fromHash && visible.includes(fromHash)) return fromHash;
  return "overview";
}

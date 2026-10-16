"use client";

import { useTranslations } from "next-intl";

/** ADR-140 §4: what a coach writes into a workout besides the prescription. */
export type WorkoutContentType = "instructions" | "scaling" | "safety" | "equipment" | "cue" | "coach-brief";
export type WorkoutContentEntry = { type: WorkoutContentType | string; body: string };

const KINDS: Array<{ type: WorkoutContentType; key: "scaling" | "safety" | "equipment" }> = [
  { type: "scaling", key: "scaling" },
  { type: "safety", key: "safety" },
  { type: "equipment", key: "equipment" },
];

export function contentOf(entries: WorkoutContentEntry[] | null | undefined, type: WorkoutContentType) {
  return (entries ?? []).filter((entry) => entry.type === type && entry.body.trim() !== "");
}

export function hasContent(entries: WorkoutContentEntry[] | null | undefined, extra?: string | null) {
  return Boolean(extra?.trim()) || (entries ?? []).some((entry) => entry.body.trim() !== "");
}

/**
 * Οδηγίες with Κλιμάκωση, Προσοχή and Εξοπλισμός under it, then «Για τον
 * coach» when the reader is staff (the server never sends a coach-brief to
 * a member). `lead` is text that reads first, such as an assignment's own
 * Οδηγίες.
 */
export function WorkoutContentBlock({
  entries,
  lead,
  title = true,
}: {
  entries: WorkoutContentEntry[] | null | undefined;
  lead?: string | null;
  title?: boolean;
}) {
  const t = useTranslations("WorkoutContent");
  const instructions = [...(lead?.trim() ? [lead.trim()] : []), ...contentOf(entries, "instructions").map((entry) => entry.body)];
  const briefs = contentOf(entries, "coach-brief");
  const kinds = KINDS.map((kind) => ({ ...kind, entries: contentOf(entries, kind.type) })).filter(
    (kind) => kind.entries.length > 0,
  );

  if (instructions.length === 0 && kinds.length === 0 && briefs.length === 0) return null;

  return (
    <section
      aria-label={t("instructions")}
      className="flex flex-col gap-2 rounded-2xl p-3 text-sm"
      style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
    >
      {title && instructions.length > 0 ? (
        <h3 className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {t("instructions")}
        </h3>
      ) : null}
      {instructions.map((body, index) => (
        <p key={`i-${index}`} className="whitespace-pre-wrap" style={{ color: "var(--text)" }}>
          {body}
        </p>
      ))}
      {kinds.map((kind) => (
        <div key={kind.type}>
          <p className="text-xs font-bold" style={{ color: kind.type === "safety" ? "var(--danger)" : "var(--primary-strong)" }}>
            {t(kind.key)}
          </p>
          {kind.entries.map((entry, index) => (
            <p key={index} className="whitespace-pre-wrap" style={{ color: "var(--text-soft)" }}>
              {entry.body}
            </p>
          ))}
        </div>
      ))}
      {briefs.length > 0 ? <CoachBrief entries={briefs} /> : null}
    </section>
  );
}

/** Cues beside one exercise, and its other content in a line each. */
export function ExerciseContent({ entries }: { entries: WorkoutContentEntry[] | null | undefined }) {
  const t = useTranslations("WorkoutContent");
  const cues = contentOf(entries, "cue");
  const kinds = KINDS.flatMap((kind) => contentOf(entries, kind.type).map((entry) => ({ key: kind.key, entry })));
  const briefs = contentOf(entries, "coach-brief");
  if (cues.length === 0 && kinds.length === 0 && briefs.length === 0) return null;

  return (
    <div className="mt-1 flex flex-col gap-1 text-xs">
      {cues.map((entry, index) => (
        <p key={`c-${index}`} className="whitespace-pre-wrap italic" style={{ color: "var(--muted)" }}>
          <span className="sr-only">{t("cue")}: </span>
          {entry.body}
        </p>
      ))}
      {kinds.map(({ key, entry }, index) => (
        <p key={`k-${index}`} className="whitespace-pre-wrap" style={{ color: "var(--muted)" }}>
          <span className="font-bold">{t(key)}:</span> {entry.body}
        </p>
      ))}
      {briefs.length > 0 ? <CoachBrief entries={briefs} /> : null}
    </div>
  );
}

function CoachBrief({ entries }: { entries: WorkoutContentEntry[] }) {
  const t = useTranslations("WorkoutContent");
  return (
    <div className="rounded-xl px-3 py-2" style={{ border: "1px dashed var(--border-strong)" }}>
      <p className="text-xs font-bold" style={{ color: "var(--dim)" }}>{t("coachBrief")}</p>
      {entries.map((entry, index) => (
        <p key={index} className="whitespace-pre-wrap text-xs" style={{ color: "var(--text-soft)" }}>
          {entry.body}
        </p>
      ))}
    </div>
  );
}

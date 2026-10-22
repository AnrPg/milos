"use client";

import { useFormatter, useTranslations } from "next-intl";
import { useState } from "react";

import type { InjuryRecord, InjuryUpdateRequest } from "@/api/wellbeing";
import { SemanticLabel } from "@/components/semantic-label";

import { timelinePositions, type InjuryEvent } from "./injury-timeline";
import { Select } from "@/components/ui/Select";

/**
 * One injury's progress (ADR-140 §3): a line with a point at every event
 * (reported, each update, healed, reopened), collapsed by default, and the
 * events below it with their text and field changes.
 */
export function InjuryTimeline({ injury }: { injury: InjuryRecord }) {
  const t = useTranslations("MemberApp.injury");
  const format = useFormatter();
  const events = injury.events as InjuryEvent[];
  const positions = timelinePositions(events);

  return (
    <details className="mt-3">
      <summary className="cursor-pointer text-sm font-bold" style={{ color: "var(--text)" }}>
        {t("timeline", { count: events.length })}
      </summary>
      <svg role="img" aria-label={t("timelineAria", { count: events.length })} viewBox="0 0 300 24" className="mt-2 h-6 w-full">
        <line x1="6" x2="294" y1="12" y2="12" stroke="var(--border)" strokeWidth="2" />
        {events.map((event, index) => (
          <circle
            key={event.id}
            cx={6 + positions[index] * 288}
            cy="12"
            r={event.event_type === "updated" ? 4 : 6}
            fill={event.event_type === "marked_healed" ? "var(--success, var(--primary))" : "var(--primary)"}
          >
            <title>{`${format.dateTime(new Date(event.occurred_at), { dateStyle: "medium" })} · ${t(`event.${event.event_type}`)}`}</title>
          </circle>
        ))}
      </svg>
      <ol className="mt-2 space-y-2">
        {events.map((event) => (
          <li key={event.id} className="rounded-2xl p-3 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            <p className="font-semibold" style={{ color: "var(--text)" }}>
              {t(`event.${event.event_type}`)}
              <span className="font-normal" style={{ color: "var(--muted)" }}>
                {" · "}
                {format.dateTime(new Date(event.occurred_at), { dateStyle: "medium", timeStyle: "short" })}
              </span>
            </p>
            {(event.payload.changes ?? []).map((change) => (
              <p key={change.field} style={{ color: "var(--muted)" }}>
                {t(`field.${change.field}`)}: <ChangeValue field={change.field} value={change.from} /> →{" "}
                <ChangeValue field={change.field} value={change.to} />
              </p>
            ))}
            {event.payload.note ? <p style={{ color: "var(--text)" }}>{event.payload.note}</p> : null}
          </li>
        ))}
      </ol>
    </details>
  );
}

function ChangeValue({ field, value }: { field: string; value: unknown }) {
  if (value === null || value === undefined || (Array.isArray(value) && value.length === 0)) return <>—</>;
  if (field === "severity") return <SemanticLabel value={value} />;
  return <>{Array.isArray(value) ? value.join(", ") : String(value)}</>;
}

/** "Add update": optional text plus severity and training limitations. */
export function InjuryUpdateForm({
  injury,
  pending,
  error,
  onSubmit,
  onCancel,
}: {
  injury: InjuryRecord;
  pending: boolean;
  error: string | null;
  onSubmit: (update: InjuryUpdateRequest) => void;
  onCancel: () => void;
}) {
  const t = useTranslations("MemberApp.injury");
  const [note, setNote] = useState("");
  const [severity, setSeverity] = useState(injury.severity);
  const [limitations, setLimitations] = useState(injury.training_limitations ?? "");

  return (
    <form
      className="mt-3 space-y-2"
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit({
          ...(note.trim() ? { note: note.trim() } : {}),
          severity,
          training_limitations: limitations,
        });
      }}
    >
      <textarea
        aria-label={t("notePlaceholder")}
        className="min-h-20 w-full rounded-2xl px-4 py-3 text-sm outline-none"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
        maxLength={2000}
        placeholder={t("notePlaceholder")}
        value={note}
        onChange={(event) => setNote(event.target.value)}
      />
      <label className="block text-xs font-semibold" style={{ color: "var(--muted)" }}>
        {t("field.severity")}
        <Select
          className="mt-1 w-full rounded-2xl px-4 py-2.5 text-sm"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          value={severity}
          onValueChange={(value) => setSeverity(value as InjuryRecord["severity"])}
        >
          {(["mild", "moderate", "severe"] as const).map((level) => (
            <option key={level} value={level}>
              {t(`severity.${level}`)}
            </option>
          ))}
        </Select>
      </label>
      <label className="block text-xs font-semibold" style={{ color: "var(--muted)" }}>
        {t("field.training_limitations")}
        <input
          className="mt-1 w-full rounded-2xl px-4 py-2.5 text-sm"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          value={limitations}
          onChange={(event) => setLimitations(event.target.value)}
        />
      </label>
      <div className="flex gap-2">
        <button
          type="submit"
          disabled={pending}
          className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {pending ? t("saving") : t("save")}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="min-h-11 rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("cancel")}
        </button>
      </div>
      {error ? <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </form>
  );
}

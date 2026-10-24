"use client";

import { useUiTranslations } from "@/i18n/ui";
import { useId, useState } from "react";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

type Props = {
  value: number | null;
  onChange: (seconds: number | null) => void;
  /** One-tap durations shown under the field, in seconds. */
  presets?: number[];
  ariaLabel?: string;
};

export const SHORT_DURATION_PRESETS = [10, 15, 20, 30, 45, 60, 90, 120];
export const LONG_DURATION_PRESETS = [300, 600, 720, 900, 1200, 1800];

/** Formats seconds as `m:ss` (or `h:mm:ss`). */
export function formatDurationInput(seconds: number | null): string {
  if (seconds === null || !Number.isFinite(seconds) || seconds <= 0) return "";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.round(seconds % 60);
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
    : `${m}:${String(s).padStart(2, "0")}`;
}

/**
 * Accepts the ways coaches type durations: `90` (seconds), `1:30`, `1:00:00`,
 * `90s`, `12m`, `1m30s`, `1h`. Returns null for an empty field and "invalid"
 * for anything else.
 */
export function parseDurationInput(text: string): number | null | "invalid" {
  const value = text.trim().toLowerCase();
  if (value === "") return null;

  if (/^\d+$/.test(value)) return Number(value);

  const clock = /^(?:(\d+):)?(\d+):(\d{2})$/.exec(value);
  if (clock) {
    const [, hours, minutes, seconds] = clock;
    if (Number(seconds) > 59 || (hours !== undefined && Number(minutes) > 59)) return "invalid";
    return Number(hours ?? 0) * 3600 + Number(minutes) * 60 + Number(seconds);
  }

  const units = /^(?:(\d+)\s*h(?:r|rs|ours?)?)?\s*(?:(\d+)\s*m(?:in|ins|inutes?)?)?\s*(?:(\d+)\s*s(?:ec|ecs|econds?)?)?$/.exec(value);
  if (units && (units[1] || units[2] || units[3])) {
    return Number(units[1] ?? 0) * 3600 + Number(units[2] ?? 0) * 60 + Number(units[3] ?? 0);
  }

  return "invalid";
}

export function TimeInput({ value, onChange, presets, ariaLabel }: Props) {
  const i18n = useUiTranslations();
  const hintId = useId();
  const [draft, setDraft] = useState<string | null>(null);
  const parsed = draft === null ? value : parseDurationInput(draft);
  const invalid = parsed === "invalid";

  return (
    <div className="flex flex-col items-end gap-1.5">
      <input
        type="text"
        inputMode="text"
        autoComplete="off"
        spellCheck={false}
        aria-label={ariaLabel}
        aria-invalid={invalid}
        aria-describedby={hintId}
        placeholder={i18n("durationInputPlaceholder")}
        value={draft ?? formatDurationInput(value)}
        onFocus={() => setDraft(formatDurationInput(value))}
        onChange={(event) => {
          const text = event.target.value;
          setDraft(text);
          const next = parseDurationInput(text);
          if (next !== "invalid") onChange(next);
        }}
        onBlur={() => setDraft(null)}
        className="w-24 rounded-lg px-2 py-1.5 text-end text-sm tabular-nums outline-none"
        style={{
          background: "var(--bg)",
          border: `1px solid ${invalid ? "var(--danger)" : "var(--dim)"}`,
          color: "var(--text)",
        }}
      />
      {invalid ? (
        <ErrorNotice variant="field" id={hintId}>{i18n("durationInputInvalid")}</ErrorNotice>
      ) : (
        <span id={hintId} className="text-[11px]" style={{ color: "var(--dim)" }}>
          {i18n("durationInputHint")}
        </span>
      )}
      {presets && presets.length > 0 ? (
        <div className="flex flex-wrap justify-end gap-1.5">
          {presets.map((preset) => (
            <button
              key={preset}
              type="button"
              aria-pressed={value === preset}
              onClick={() => {
                setDraft(null);
                onChange(preset);
              }}
              className="min-h-8 rounded-full px-2.5 text-xs font-semibold tabular-nums"
              style={
                value === preset
                  ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                  : { border: "1px solid var(--border)", color: "var(--text-soft)" }
              }
            >
              {formatDurationInput(preset)}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}

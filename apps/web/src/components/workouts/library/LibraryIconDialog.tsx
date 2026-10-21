"use client";

import { useState } from "react";

import { useUiTranslations } from "@/i18n/ui";

import { ICON_CHOICES } from "./library-folders";

/** Lets a coach pick a workout's icon, type any emoji, or go back to automatic. */
export function LibraryIconDialog({
  workoutTitle,
  currentIcon,
  automaticIcon,
  isCustom,
  busy,
  onCancel,
  onSave,
}: {
  workoutTitle: string;
  currentIcon: string;
  /** What the rules (or AI) would show if the coach resets to automatic. */
  automaticIcon: string;
  isCustom: boolean;
  busy: boolean;
  onCancel: () => void;
  onSave: (icon: string | null) => void;
}) {
  const i18n = useUiTranslations();
  const [selected, setSelected] = useState(currentIcon);
  const [typed, setTyped] = useState("");
  const choice = typed.trim() || selected;

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center p-4" style={{ background: "var(--scrim)" }} onClick={onCancel} role="presentation">
      <form
        role="dialog"
        aria-modal="true"
        aria-label={i18n("featureChangeIconTitle", { name: workoutTitle })}
        className="w-full max-w-md rounded-[1.5rem] p-5 shadow-[var(--shadow-lg)]"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        onClick={(event) => event.stopPropagation()}
        onSubmit={(event) => {
          event.preventDefault();
          onSave(choice);
        }}
      >
        <div className="flex items-center gap-3">
          <span aria-hidden className="grid h-12 w-12 shrink-0 place-items-center rounded-xl text-3xl" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            {choice}
          </span>
          <h2 className="min-w-0 text-lg font-semibold" style={{ color: "var(--text)" }}>
            {i18n("featureChangeIconTitle", { name: workoutTitle })}
          </h2>
        </div>

        <div role="radiogroup" aria-label={i18n("featureIconChoices")} className="mt-4 grid grid-cols-8 gap-1">
          {ICON_CHOICES.map((icon) => (
            <button
              key={icon}
              type="button"
              role="radio"
              aria-checked={!typed.trim() && selected === icon}
              aria-label={icon}
              className="grid aspect-square place-items-center rounded-lg text-xl hover:bg-[var(--panel-muted)]"
              style={!typed.trim() && selected === icon ? { background: "color-mix(in srgb, var(--primary) 18%, transparent)", outline: "2px solid var(--primary)" } : undefined}
              onClick={() => {
                setTyped("");
                setSelected(icon);
              }}
            >
              {icon}
            </button>
          ))}
        </div>

        <label className="mt-4 block text-sm font-semibold" style={{ color: "var(--muted)" }}>
          {i18n("featureCustomIcon")}
          <input
            className="mt-2 w-full rounded-xl px-3 py-2 text-sm"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            value={typed}
            maxLength={16}
            onChange={(event) => setTyped(event.target.value)}
          />
        </label>

        <div className="mt-5 flex flex-wrap items-center justify-between gap-2">
          <button
            type="button"
            disabled={busy || !isCustom}
            className="text-sm font-semibold underline-offset-2 hover:underline disabled:opacity-40"
            style={{ color: "var(--text-soft)" }}
            onClick={() => onSave(null)}
          >
            {i18n("featureAutomaticIcon", { icon: automaticIcon })}
          </button>
          <div className="flex gap-2">
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={onCancel}>
              {i18n("cancel77dfd21")}
            </button>
            <button type="submit" disabled={busy || !choice} className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {i18n("saveefc007a")}
            </button>
          </div>
        </div>
      </form>
    </div>
  );
}

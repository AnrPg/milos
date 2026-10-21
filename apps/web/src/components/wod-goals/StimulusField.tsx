"use client";

import { useId } from "react";
import { useTranslations } from "next-intl";

import { insertPhrase, STIMULUS_MAX_LENGTH } from "@/lib/wod-goals/goals";

const PHRASES = ["unbroken", "steady", "heavy", "technique"] as const;

/** Stimulus (Q5): free text up to 280 characters with tap-to-insert phrases. */
export function StimulusField({ value, timeDomain, onChange }: { value: string; timeDomain: string | null; onChange: (value: string) => void }) {
  const t = useTranslations("WodGoals");
  const id = useId();
  const phrases = [...(timeDomain ? [timeDomain] : []), ...PHRASES.map((phrase) => t(`phrase.${phrase}`))];
  return (
    <div className="flex flex-col gap-2">
      <label htmlFor={id} className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {t("stimulus")}
      </label>
      <textarea
        id={id}
        value={value}
        maxLength={STIMULUS_MAX_LENGTH}
        rows={2}
        onChange={(event) => onChange(event.target.value)}
        placeholder={t("stimulusPlaceholder")}
        className="w-full rounded-xl border px-3 py-2 text-sm outline-none"
        style={{ background: "var(--card, var(--panel))", borderColor: "var(--dim, var(--border))", color: "var(--text)" }}
      />
      <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label={t("stimulusPhrases")}>
        {phrases.map((phrase) => (
          <button
            key={phrase}
            type="button"
            onClick={() => onChange(insertPhrase(value, phrase))}
            className="min-h-8 rounded-full px-2.5 text-xs font-semibold"
            style={{ background: "var(--bg)", color: "var(--text-soft, var(--muted))", border: "1px dashed var(--border)" }}
          >
            {phrase}
          </button>
        ))}
        <span className="ms-auto text-[10px] tabular-nums" style={{ color: "var(--dim)" }}>
          {value.length}/{STIMULUS_MAX_LENGTH}
        </span>
      </div>
    </div>
  );
}

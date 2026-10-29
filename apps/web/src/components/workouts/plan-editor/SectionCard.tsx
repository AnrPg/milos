"use client";

import { useTranslations } from "next-intl";

import { FLOWS, summary } from "@/lib/structured-plan";
import { focusKey, usePlanEditorStore, type PlanEditorSection } from "@/stores/structured-plan";

import { useKeyText, usePlanText } from "./plan-text";

/** A, B, C… for the section at `index`. */
export const sectionLetter = (index: number) => String.fromCharCode(65 + (index % 26));

/**
 * A closed section in one line: letter, flow, preset (grey chip), name, the
 * exercises and the clock's parameters. Enter or a click opens it.
 */
export function SectionCard({ section, index }: { section: PlanEditorSection; index: number }) {
  const t = useTranslations("PlanEditor");
  const k = useKeyText();
  const words = usePlanText();
  const openSection = usePlanEditorStore((s) => s.openSection);
  const { plan } = section;
  const sum = summary(plan);
  const what = sum.names.map((block) => block.map((n) => (n.perSide ? `${n.name} (${t("perSide")})` : n.name)).join(" + ")).join(" / ");
  const params = sum.params.map(words).join(" · ");
  const presetKey = plan.preset ? `PlanCore.preset.${plan.preset}` : null;

  return (
    <button
      type="button"
      data-testid="plan-section-card"
      data-k={focusKey.card(section.id)}
      onClick={() => openSection(section.id)}
      className="flex w-full min-w-0 flex-wrap items-center gap-x-3 gap-y-1 rounded-xl border px-3 py-2.5 text-start outline-none focus-visible:border-[var(--primary)] focus-visible:ring-2 focus-visible:ring-[var(--focus-ring)]"
      style={{ background: "var(--card)", borderColor: "var(--border)", color: "var(--text)" }}
    >
      <span className="grid h-6 w-6 shrink-0 place-items-center rounded-md text-xs font-bold" style={{ background: "var(--text)", color: "var(--bg)" }}>
        {sectionLetter(index)}
      </span>
      <span className="font-bold" style={{ color: "var(--primary)" }}>{k(FLOWS[plan.flow].labelKey)}</span>
      {presetKey ? (
        <span className="rounded-full border border-dashed px-2 text-xs" title={t("presetChip")} style={{ borderColor: "var(--border-strong)", color: "var(--muted)" }}>
          {k(presetKey)}
        </span>
      ) : null}
      {section.name ? <b className="text-sm">{section.name}</b> : null}
      <span className="min-w-0 flex-1 break-words text-sm" style={{ color: "var(--text-soft)" }}>
        {what || t("noExercises")}
      </span>
      {params ? <span className="text-xs" style={{ color: "var(--muted)" }}>{params}</span> : null}
    </button>
  );
}

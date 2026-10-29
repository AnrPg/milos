"use client";

import { useTranslations } from "next-intl";

import { FLOWS, MODS, describe, human, parseClock, parseTimes, type ParamDef } from "@/lib/structured-plan";
import { focusKey, usePlanEditorStore, type PlanEditorSection } from "@/stores/structured-plan";

import { useKeyText, usePlanText } from "./plan-text";
import { Timeline } from "./Timeline";

const COUNT_UNITS: Partial<Record<string, "rounds" | "times" | "sets" | "hrTarget">> = { rounds: "rounds", times: "times", sets: "sets", hrTarget: "hrTarget" };

/** The unit shown next to a parameter's value: never a guess, nothing when the value says it. */
export function paramUnit(def: ParamDef, value: string): "rounds" | "times" | "sets" | "hrTarget" | "min" | "sec" | "clock" | null {
  if (def.kind === "count" || def.kind === "range") return COUNT_UNITS[def.key] ?? null;
  if (def.kind === "text") return null;
  const v = value.trim();
  if (!v) return def.bare === "min" ? "min" : "clock";
  if (/[:s″"′'λδ]|min/.test(v)) return null;
  return def.kind === "times" || def.bare === "min" || Number(v.split(/[-,]/)[0]) <= 10 ? "min" : "sec";
}

/** How the value reads ("= 1 λεπτό 30 δευτ."), or null when it is empty; "bad" when it does not read. */
function useReading() {
  const t = useTranslations("PlanEditor");
  const words = usePlanText();
  return (def: ParamDef, value: string): string | "bad" | null => {
    const v = value.trim();
    if (!v) return null;
    if (def.kind === "count") return /^\d+$/.test(v) ? null : "bad";
    if (def.kind === "range") return /^\d+(\s*-\s*\d+)?$/.test(v) ? null : "bad";
    if (def.kind === "time") {
      const secs = parseClock(v, def.bare);
      return secs === "bad" || secs === null ? "bad" : t("reading", { text: words(human(secs)) });
    }
    if (def.kind === "times") {
      const w = parseTimes(v, "min");
      if (w === "bad" || w === null) return "bad";
      return w.secs.length > 1
        ? t("readingWindows", { count: w.secs.length, list: w.secs.map((s) => words(human(s))).join(", ") })
        : t("reading", { text: words(human(w.secs[0])) });
    }
    return null;
  };
}

function ParamField({ section, def }: { section: PlanEditorSection; def: ParamDef }) {
  const t = useTranslations("PlanEditor");
  const k = useKeyText();
  const setParam = usePlanEditorStore((s) => s.setParam);
  const read = useReading();
  const value = section.plan.params[def.key] ?? "";
  const reading = read(def, value);
  const bad = reading === "bad";
  const unit = paramUnit(def, value);
  const example =
    def.kind === "times" ? t("example.times") : def.kind === "time" ? (def.bare === "min" ? t("example.timeMin") : t("example.timeSmart")) : def.kind === "range" ? t("example.range") : def.kind === "count" ? t("example.count") : "";
  const label = k(def.labelKey);
  return (
    <label className="flex min-w-0 flex-col gap-1 text-sm font-semibold">
      {label}
      <span className="flex items-center gap-1.5">
        <input
          data-testid={`plan-param-${def.key}`}
          data-k={focusKey.param(section.id, def.key)}
          value={value}
          aria-label={label}
          aria-invalid={bad || undefined}
          autoComplete="off"
          placeholder={def.kind === "time" || def.kind === "times" ? t("unit.clock") : ""}
          onChange={(e) => setParam(section.id, def.key, e.target.value)}
          className={`${def.kind === "times" ? "w-36" : "w-24"} rounded-lg border px-2.5 py-1.5 text-base font-bold outline-none focus:border-[var(--primary)]`}
          style={{ background: "var(--control-bg)", borderColor: bad ? "var(--danger)" : "var(--control-border)", color: "var(--text)" }}
        />
        {unit ? <span className="text-sm font-normal" aria-hidden="true" style={{ color: "var(--muted)" }}>{t(`unit.${unit}`)}</span> : null}
      </span>
      <span className="text-xs font-normal" style={{ color: bad ? "var(--danger-strong)" : "var(--muted)" }}>
        {reading && reading !== "bad" ? reading : example}
      </span>
    </label>
  );
}

/**
 * Step Χρόνος: only this flow's fields, each with its unit next to the value
 * and a quiet reading under it; add-ons (interrupt, heart rate) as quiet «+»
 * buttons; one sentence describing the section; the timeline.
 */
export function StepTime({ section }: { section: PlanEditorSection }) {
  const t = useTranslations("PlanEditor");
  const k = useKeyText();
  const words = usePlanText();
  const toggleMod = usePlanEditorStore((s) => s.toggleMod);
  const { plan } = section;
  const flow = FLOWS[plan.flow];
  const sentence = describe(plan).map(words).join(" ");
  const off = flow.mods.filter((m) => !plan.mods?.[m]);
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-start gap-x-5 gap-y-3">
        {flow.params.map((def) => <ParamField key={def.key} section={section} def={def} />)}
        {flow.mods
          .filter((m) => plan.mods?.[m])
          .map((m) => (
            <div key={m} className="flex flex-wrap items-start gap-2">
              {MODS[m].params.map((def) => <ParamField key={def.key} section={section} def={def} />)}
              <button
                type="button"
                data-testid={`plan-mod-remove-${m}`}
                title={t("removeModTitle")}
                onClick={() => toggleMod(section.id, m)}
                className="mt-6 rounded-full border border-dashed px-3 py-1 text-sm"
                style={{ borderColor: "var(--border-strong)", color: "var(--muted)" }}
              >
                {t("removeMod", { label: k(MODS[m].labelKey) })}
              </button>
            </div>
          ))}
      </div>
      {off.length ? (
        <div className="flex flex-wrap gap-2">
          {off.map((m) => (
            <button
              key={m}
              type="button"
              data-testid={`plan-mod-add-${m}`}
              title={k(MODS[m].hintKey)}
              onClick={() => toggleMod(section.id, m)}
              className="rounded-full border border-dashed px-3 py-1 text-sm"
              style={{ borderColor: "var(--border-strong)", color: "var(--text-soft)" }}
            >
              {t("addMod", { label: k(MODS[m].labelKey) })}
            </button>
          ))}
        </div>
      ) : null}
      {sentence ? <p data-testid="plan-sentence" className="text-sm" style={{ color: "var(--text)" }}>{sentence}</p> : null}
      <Timeline plan={plan} />
    </div>
  );
}

"use client";

import { useTranslations } from "next-intl";
import { useId, useMemo, useState, type CSSProperties, type KeyboardEvent, type ReactNode } from "react";

import { FLOWS, FLOW_KEYS, PRESETS, STRUCTS, rankItems, type PlanFlow, type PresetDef } from "@/lib/structured-plan";
import { focusKey, usePlanEditorStore, type PlanEditorSection } from "@/stores/structured-plan";

import { useKeyText } from "./plan-text";

type Item = { type: "flow"; flow: PlanFlow } | { type: "preset"; preset: PresetDef };

/** Highlights the matched ranges of a label. */
function Marked({ text, marks }: { text: string; marks: [number, number][] }) {
  if (!marks.length) return <>{text}</>;
  const out: ReactNode[] = [];
  let at = 0;
  marks
    .slice()
    .sort((a, b) => a[0] - b[0])
    .forEach(([from, to], i) => {
      if (from < at) return;
      out.push(text.slice(at, from));
      out.push(
        <mark key={i} className="rounded-sm" style={{ background: "var(--highlight)", color: "var(--highlight-text)" }}>
          {text.slice(from, to)}
        </mark>,
      );
      at = to;
    });
  out.push(text.slice(at));
  return <>{out}</>;
}

/**
 * Step Ροή: one combobox with fuzzy ranking. Flows come first; presets sit
 * apart in a grey box, grouped under the flow they fill in (a different IA
 * level: shortcuts into a flow, never more flows). ↑ ↓ choose, Enter picks.
 */
export function StepFlow({ section }: { section: PlanEditorSection }) {
  const t = useTranslations("PlanEditor");
  const k = useKeyText();
  const setFlow = usePlanEditorStore((s) => s.setFlow);
  const applyPreset = usePlanEditorStore((s) => s.applyPreset);
  const [query, setQuery] = useState("");
  // null: the best match, wherever it sits in the list
  const [pick, setPick] = useState<number | null>(null);
  const listId = useId();

  const recipe = (p: PresetDef): string => {
    const v = p.params ?? {};
    const parts: string[] = [];
    if (p.flow === "intervals") parts.push(p.mods?.hr && !v.off ? t("recipe.intervalsHr", { work: v.work ?? "", rounds: v.rounds ?? "" }) : t("recipe.intervals", { work: v.work ?? "", off: v.off ?? "", rounds: v.rounds ?? "" }));
    if (p.flow === "amrap" && v.dur) parts.push(t("recipe.amrap", { dur: v.dur }));
    if (p.slots) parts.push(t("recipe.slots", { count: p.slots }));
    if (p.struct && p.struct !== p.key) parts.push(k(STRUCTS[p.struct].labelKey));
    if (p.reps) parts.push(t("recipe.reps", { reps: p.reps }));
    if (p.mods?.interrupt) parts.push(t("recipe.interrupt"));
    if (p.mods?.hr) parts.push(t("recipe.hr"));
    return parts.join(" · ");
  };

  const ranked = useMemo(() => {
    const items: Item[] = [...FLOW_KEYS.map((flow): Item => ({ type: "flow", flow })), ...PRESETS.map((preset): Item => ({ type: "preset", preset }))];
    return rankItems(query, items, (it) =>
      it.type === "flow"
        ? { label: k(FLOWS[it.flow].labelKey), alt: `${FLOWS[it.flow].aliases.join(" ")} ${k(FLOWS[it.flow].hintKey)}`, bonus: 1 }
        : { label: k(it.preset.labelKey), alt: `${it.preset.aliases.join(" ")} ${k(FLOWS[it.preset.flow].labelKey)}` },
    );
  }, [query, k]);

  // Display order: flows, then presets grouped under their flow (in flow order).
  const flows = ranked.filter((r) => r.item.type === "flow");
  const presetGroups = FLOW_KEYS.map((flow) => [flow, ranked.filter((r) => r.item.type === "preset" && r.item.preset.flow === flow)] as const).filter(([, xs]) => xs.length);
  const order = [...flows, ...presetGroups.flatMap(([, xs]) => xs)];
  const active = pick === null ? Math.max(0, order.indexOf(ranked[0])) : Math.min(pick, Math.max(order.length - 1, 0));
  const current = order[active];

  const choose = (it: Item) => (it.type === "flow" ? setFlow(section.id, it.flow) : applyPreset(section.id, it.preset.key));
  const optionId = (i: number) => `${listId}-o${i}`;

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if ((e.key === "ArrowDown" || e.key === "ArrowUp") && !e.altKey && order.length) {
      e.preventDefault();
      setPick((active + (e.key === "ArrowDown" ? 1 : -1) + order.length) % order.length);
    } else if (e.key === "Enter" && !e.shiftKey && !e.altKey && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      if (current) choose(current.item);
    }
  };

  const option = (r: (typeof order)[number], body: ReactNode, className: string, style: CSSProperties) => {
    const i = order.indexOf(r);
    const selected = i === active;
    return (
      <div
        key={r.item.type === "flow" ? r.item.flow : r.item.preset.key}
        id={optionId(i)}
        role="option"
        aria-selected={selected}
        data-testid={r.item.type === "flow" ? `plan-flow-option-${r.item.flow}` : `plan-preset-option-${r.item.preset.key}`}
        onMouseDown={(e) => {
          e.preventDefault();
          choose(r.item);
        }}
        className={`${className} cursor-pointer`}
        style={{ ...style, ...(selected ? { borderColor: "var(--primary)", boxShadow: "0 0 0 1px var(--primary)" } : {}) }}
      >
        {body}
      </div>
    );
  };

  return (
    <div className="flex flex-col gap-3">
      <input
        data-testid="plan-flow-input"
        data-k={focusKey.pick(section.id)}
        role="combobox"
        aria-expanded="true"
        aria-controls={listId}
        aria-activedescendant={current ? optionId(active) : undefined}
        aria-label={t("flowInput")}
        autoComplete="off"
        value={query}
        placeholder={t("flowPlaceholder")}
        onChange={(e) => {
          setQuery(e.target.value);
          setPick(null);
        }}
        onKeyDown={onKeyDown}
        className="w-full text-ellipsis rounded-xl border border-[var(--control-border)] px-3 py-2.5 text-base outline-none focus:border-[var(--primary)] focus:shadow-[0_0_0_1px_var(--primary)]"
        style={{ background: "var(--control-bg)", color: "var(--text)" }}
      />
      <div id={listId} role="listbox" aria-label={t("flowInput")} className="flex flex-col gap-3">
        {flows.length ? (
          <div className="flex flex-col gap-1.5">
            <span className="text-xs font-bold uppercase tracking-wide" style={{ color: "var(--muted)" }}>{t("flowsHeading")}</span>
            <div className="grid grid-cols-1 gap-1.5 sm:grid-cols-2">
              {flows.map((r) =>
                r.item.type === "flow"
                  ? option(
                      r,
                      <>
                        <b className="block"><Marked text={k(FLOWS[r.item.flow].labelKey)} marks={r.onLabel ? r.marks : []} /></b>
                        <span className="text-xs" style={{ color: "var(--muted)" }}>{k(FLOWS[r.item.flow].hintKey)}</span>
                      </>,
                      "rounded-lg border px-3 py-2",
                      { background: "var(--card)", borderColor: "var(--border)" },
                    )
                  : null,
              )}
            </div>
          </div>
        ) : null}
        {presetGroups.length ? (
          <div data-testid="plan-presets" className="flex flex-col gap-2 rounded-xl p-3" style={{ background: "var(--panel-muted)" }}>
            <div className="flex flex-wrap items-baseline gap-x-2">
              <span className="text-xs font-bold uppercase tracking-wide" style={{ color: "var(--muted)" }}>{t("presetsHeading")}</span>
              <span className="text-xs" style={{ color: "var(--muted)" }}>{t("presetsSub")}</span>
            </div>
            {presetGroups.map(([flow, xs]) => (
              <div key={flow} className="flex flex-wrap items-center gap-2">
                <span className="w-24 shrink-0 text-xs font-bold uppercase" style={{ color: "var(--primary)" }}>{k(FLOWS[flow].labelKey)}</span>
                <div className="flex min-w-0 flex-1 flex-wrap gap-1.5">
                  {xs.map((r) =>
                    r.item.type === "preset"
                      ? option(
                          r,
                          <Marked text={k(r.item.preset.labelKey)} marks={r.onLabel ? r.marks : []} />,
                          "rounded-full border border-dashed px-3 py-1 text-sm font-semibold",
                          { background: "var(--panel)", borderColor: "var(--border-strong)" },
                        )
                      : null,
                  )}
                </div>
              </div>
            ))}
            <div className="min-h-4 text-xs" aria-live="polite" style={{ color: "var(--muted)" }}>
              {current?.item.type === "preset"
                ? [t("presetIs", { preset: k(current.item.preset.labelKey), flow: k(FLOWS[current.item.preset.flow].labelKey) }), recipe(current.item.preset)].filter(Boolean).join(" · ")
                : null}
            </div>
          </div>
        ) : null}
        {!order.length ? <p className="p-2 text-sm" style={{ color: "var(--muted)" }}>{t("noMatch")}</p> : null}
      </div>
    </div>
  );
}

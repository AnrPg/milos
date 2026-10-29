"use client";

import { useTranslations } from "next-intl";

import { clock, paramSecs, timeline, type PlanSection } from "@/lib/structured-plan";

/** Slot colours (alternating blocks), theme variables only. */
const SLOT = ["var(--primary)", "var(--info)", "var(--heat)"];
const REST = "var(--panel-muted)";
const INTERRUPT = "var(--heat)";

/** The shape of the section's clock as coloured bars; nothing for flows without a clock. */
export function Timeline({ plan }: { plan: PlanSection }) {
  const t = useTranslations("PlanEditor");
  const { segments, interrupts, total } = timeline(plan);
  if (!segments.length || !total) return null;
  const width = 1000;
  const starts = segments.reduce<number[]>((acc, seg, i) => [...acc, (acc[i] ?? 0) + seg.secs], [0]);
  const bars = segments.map((seg, i) => {
    const w = (seg.secs / total) * width;
    const fill = seg.kind === "rest" ? REST : SLOT[(seg.slot ?? 0) % SLOT.length];
    return <rect key={i} x={(starts[i] / total) * width + 1} y={4} width={Math.max(w - 2, 1)} height={22} rx={3} fill={fill} />;
  });
  const every = plan.mods?.interrupt ? paramSecs(plan, "intEvery") : null;
  const slots = (plan.flow === "emom" || plan.flow === "intervals") && plan.blocks.length > 1 ? plan.blocks.length : 0;
  return (
    <div data-testid="plan-timeline">
      <svg viewBox={`0 0 ${width} 30`} preserveAspectRatio="none" role="img" aria-label={t("timeline")} className="block h-8 w-full">
        {bars}
        {interrupts.map((at) => (
          <rect key={`i${at}`} x={(at / total) * width - 3} y={0} width={6} height={30} rx={2} fill={INTERRUPT} />
        ))}
      </svg>
      <div className="mt-1 flex flex-wrap items-center gap-x-3 text-xs" style={{ color: "var(--muted)" }}>
        <span>0:00</span>
        {every ? (
          <span className="flex items-center gap-1">
            <i className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: INTERRUPT }} />
            {t("timelineInterrupt", { every: clock(every) })}
          </span>
        ) : null}
        {Array.from({ length: slots }, (_, i) => (
          <span key={i} className="flex items-center gap-1">
            <i className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: SLOT[i % SLOT.length] }} />
            {t("timelineSlot", { n: i + 1 })}
          </span>
        ))}
        <span className="ms-auto">{clock(total)}</span>
      </div>
    </div>
  );
}

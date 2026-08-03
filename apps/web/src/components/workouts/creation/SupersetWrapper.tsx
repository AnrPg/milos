"use client";

import { useUiTranslations } from "@/i18n/ui";

import { NumberStepper } from "./NumberStepper";

type Props = {
  children: React.ReactNode;
  kind: "superset" | "alternating";
  color: string;
  sets: number;
  onSetsChange: (sets: number) => void;
};

export function SupersetWrapper({ children, color, kind, onSetsChange, sets }: Props) {
  const i18n = useUiTranslations();

  return (
    <section className="my-1 rounded-lg p-3" style={{ border: `1px solid color-mix(in srgb, ${color} 45%, var(--border))` }}>
      <header className="mb-2 flex items-center gap-2">
        <span className="text-xs font-bold uppercase" style={{ color }}>
          {kind === "superset" ? i18n("supersetLabel") : i18n("alternatingSetsLabel")}
        </span>
        <div className="flex items-center gap-1" style={{ color }}>
          <NumberStepper min={1} onChange={onSetsChange} value={sets} />
          <span className="text-xs font-semibold">{i18n("setsd6c8220")}</span>
        </div>
        <div className="h-px flex-1" style={{ background: color, opacity: 0.25 }} />
      </header>
      <div className="flex flex-col gap-2">{children}</div>
    </section>
  );
}

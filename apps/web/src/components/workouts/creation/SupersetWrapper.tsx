"use client";

import { useUiTranslations } from "@/i18n/ui";

type Props = {
  children: React.ReactNode;
  kind: "superset" | "alternating";
};

export function SupersetWrapper({ children, kind }: Props) {
  const i18n = useUiTranslations();
  const color = kind === "superset" ? "var(--primary)" : "var(--info)";

  return (
    <div className="my-1 ps-3" style={{ borderInlineStart: `3px solid ${color}` }}>
      <div className="mb-2 flex items-center gap-2">
        <span className="text-xs font-bold uppercase" style={{ color }}>
          {kind === "superset" ? i18n("supersetLabel") : i18n("alternatingSetsLabel")}
        </span>
        <div className="h-px flex-1" style={{ background: color, opacity: 0.25 }} />
      </div>
      <div className="flex flex-col gap-2">{children}</div>
    </div>
  );
}

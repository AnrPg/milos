"use client";

import { usePathname, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { DialogButton } from "@/components/ui/Dialog";
import { availableGuides, progressFor, shouldOffer } from "@/lib/guides/engine";
import { GUIDES } from "@/lib/guides/registry";

import { useOptionalGuides } from "./GuideProvider";

/**
 * ADR-193: on a guide's home screen, the first visit offers its walkthrough
 * once, as a small card that never blocks the screen. «Not now» is final
 * here (the guides list still has it); «Show me» starts it.
 */
export function GuideOffer() {
  const t = useTranslations("Guides");
  const guides = useOptionalGuides();
  const pathname = usePathname() ?? "/";
  const search = useSearchParams().toString();
  const [hidden, setHidden] = useState<string[]>([]);
  if (!guides || guides.active || !guides.progress) return null;
  const guide = availableGuides(GUIDES, guides.abilities).find(
    (entry) => !hidden.includes(entry.id) && shouldOffer(entry, progressFor(guides.progress, entry.id), pathname, search),
  );
  if (!guide) return null;
  const title = t(`${guide.id}.title` as never);

  return (
    <aside
      aria-label={title}
      data-testid="guide-offer"
      className="fixed inset-x-3 bottom-[calc(var(--bottom-float-inset,0px)+5rem)] z-(--z-sticky) flex flex-col gap-3 rounded-3xl p-4 shadow-lg sm:inset-x-auto sm:start-4 sm:w-80"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div>
        <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("ui.offerEyebrow")}</p>
        <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("ui.offerBody", { title, minutes: t("ui.minutes", { count: guide.minutes }) })}
        </p>
        <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>{t(`${guide.id}.summary` as never)}</p>
      </div>
      <div className="flex gap-2">
        <DialogButton
          tone="ghost"
          className="flex-1"
          onClick={() => {
            setHidden((current) => [...current, guide.id]);
            guides.dismiss(guide.id);
          }}
        >
          {t("ui.offerLater")}
        </DialogButton>
        <DialogButton tone="primary" className="flex-1" onClick={() => guides.start(guide.id)} testId="guide-offer-start">
          {t("ui.offerStart")}
        </DialogButton>
      </div>
    </aside>
  );
}

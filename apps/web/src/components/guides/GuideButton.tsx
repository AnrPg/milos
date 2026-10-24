"use client";

import { useTranslations } from "next-intl";

import { pageHeaderActionClass } from "@/components/PageHeader";
import { guideState, progressFor } from "@/lib/guides/engine";
import { guideById } from "@/lib/guides/registry";
import type { GuideId } from "@/lib/guides/types";

import { useOptionalGuides } from "./GuideProvider";

/**
 * «Walkthrough» in a screen's header (ADR-193): starts that screen's guide,
 * or resumes it where it was left. Shown only to people the guide is for.
 */
export function GuideButton({ guide: id, className = pageHeaderActionClass }: { guide: GuideId; className?: string }) {
  const t = useTranslations("Guides");
  const guides = useOptionalGuides();
  if (!guides) return null;
  const guide = guideById(id);
  if (!guide.requires(guides.abilities)) return null;
  const resume = guideState(guide, progressFor(guides.progress, id)) === "started";
  const title = t(`${id}.title` as never);
  return (
    <button
      type="button"
      onClick={() => guides.start(id, { resume })}
      aria-label={t("ui.openGuideAria", { title })}
      className={`${className} inline-flex items-center gap-1.5`}
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
      data-testid={`guide-button-${id}`}
    >
      <span aria-hidden="true">▶</span>
      {t("ui.openGuide")}
    </button>
  );
}

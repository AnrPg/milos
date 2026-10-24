"use client";

import { useTranslations } from "next-intl";

import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { BackToMe } from "@/components/member-app/me/BackToMe";
import { DialogButton } from "@/components/ui/Dialog";
import { availableGuides, guideState, progressFor, type GuideState } from "@/lib/guides/engine";
import { GUIDES } from "@/lib/guides/registry";
import type { Guide } from "@/lib/guides/types";

import { useGuides } from "./GuideProvider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const STATE_TONE: Record<GuideState, string> = {
  new: "var(--primary-strong, var(--primary))",
  started: "var(--info)",
  completed: "var(--success)",
  dismissed: "var(--dim)",
  outdated: "var(--warning)",
};

/** Εγώ › Guides (ADR-193): the walkthroughs for the business first, then the ones for you. */
export function GuidesPage() {
  const t = useTranslations("Guides");
  const guides = useGuides();
  const list = availableGuides(GUIDES, guides.abilities);
  const groups = [
    { key: "forStaff", items: list.filter((guide) => guide.audience === "staff") },
    { key: "forYou", items: list.filter((guide) => guide.audience === "member") },
  ].filter((group) => group.items.length > 0);

  return (
    <HubPage back={<BackToMe />} title={t("ui.listTitle")}>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("ui.listIntro")}</p>
      {guides.progressError ? (
        <ErrorNotice>{t("ui.loadFailed")}</ErrorNotice>
      ) : null}
      {groups.map((group) => (
        <HubCard key={group.key} eyebrow={t(`ui.${group.key}` as never)}>
          <ul className="flex flex-col gap-3" data-testid="guides-list">
            {group.items.map((guide) => (
              <GuideRow key={guide.id} guide={guide} />
            ))}
          </ul>
        </HubCard>
      ))}
    </HubPage>
  );
}

function GuideRow({ guide }: { guide: Guide }) {
  const t = useTranslations("Guides");
  const guides = useGuides();
  const state = guideState(guide, progressFor(guides.progress, guide.id));
  const action = state === "started" ? "resume" : state === "completed" || state === "outdated" ? "replay" : "start";
  const title = t(`${guide.id}.title` as never);
  return (
    <li className="flex items-center gap-3 rounded-2xl p-3" style={{ background: "var(--panel-raised)" }} data-testid={`guide-row-${guide.id}`}>
      <div className="min-w-0 grow">
        <p className="font-bold" style={{ color: "var(--text)" }}>{title}</p>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`${guide.id}.summary` as never)}</p>
        <p className="mt-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("ui.minutes", { count: guide.minutes })}
          {guides.progress ? (
            <>
              {" · "}
              <span style={{ color: STATE_TONE[state] }}>{t(`ui.state_${state}` as never)}</span>
            </>
          ) : null}
        </p>
      </div>
      <DialogButton
        tone={action === "replay" ? "secondary" : "primary"}
        onClick={() => guides.start(guide.id, { resume: action === "resume" })}
        className="shrink-0"
      >
        <span className="sr-only">{t("ui.openGuideAria", { title })}</span>
        <span aria-hidden="true">{t(`ui.${action}` as never)}</span>
      </DialogButton>
    </li>
  );
}

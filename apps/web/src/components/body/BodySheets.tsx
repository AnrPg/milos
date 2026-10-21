"use client";

import { useId, useState } from "react";
import { useTranslations } from "next-intl";

import type { WeightDisplay } from "@/api/body";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { key } from "@/components/body/BodyBits";

/**
 * The body-photo consent, asked before the first photo ever (ADR-158 §4,
 * board 13 q6), in plain words: what is kept, who sees it, that it can all
 * be deleted. «Χωρίς φωτογραφίες» carries on with numbers only.
 */
export function PhotoConsentSheet({
  onAgree,
  onDecline,
  busy,
  error,
}: {
  onAgree: () => void;
  onDecline: () => void;
  busy: boolean;
  error: string | null;
}) {
  const t = useTranslations("Body");
  const labelId = useId();
  return (
    <Sheet
      labelId={labelId}
      title={t("consentTitle")}
      onClose={onDecline}
      footer={
        <>
          <SheetButton onClick={onDecline}>{t("consentDecline")}</SheetButton>
          <SheetButton primary disabled={busy} onClick={onAgree}>{t("consentAgree")}</SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-3 text-sm" style={{ color: "var(--text-soft)" }}>
        <p className="font-semibold" style={{ color: "var(--text)" }}>{t("consentLead")}</p>
        <ul className="list-disc space-y-1 ps-5">
          <li>{t("consentStored")}</li>
          <li>{t("consentWho")}</li>
          <li>{t("consentDelete")}</li>
        </ul>
        <ErrorLine message={error} />
      </div>
    </Sheet>
  );
}

const DISPLAYS: WeightDisplay[] = ["number", "trend", "hidden"];

/** «Πώς θες να βλέπεις το βάρος;» asked with the first weight (board 13 q2). */
export function WeightDisplaySheet({
  onChoose,
  onClose,
  busy,
}: {
  onChoose: (choice: WeightDisplay) => void;
  onClose: () => void;
  busy: boolean;
}) {
  const t = useTranslations("Body");
  const labelId = useId();
  const [choice, setChoice] = useState<WeightDisplay>("number");
  return (
    <Sheet
      labelId={labelId}
      title={t("weightDisplayQuestion")}
      onClose={onClose}
      footer={<SheetButton primary disabled={busy} onClick={() => onChoose(choice)}>{t("saveChoice")}</SheetButton>}
    >
      <div className="flex flex-col gap-3">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("weightDisplayIntro")}</p>
        <div role="radiogroup" aria-label={t("weightDisplayQuestion")} className="flex flex-col gap-2">
          {DISPLAYS.map((item) => (
            <ChoicePill key={item} selected={choice === item} onSelect={() => setChoice(item)} hint={t(key("weightDisplayHint", item))}>
              {t(key("weightDisplay", item))}
            </ChoicePill>
          ))}
        </div>
      </div>
    </Sheet>
  );
}

const HELP = ["waist", "hips", "chest", "arm", "thigh", "neck", "calf"] as const;

/** «Πώς μετράω;»: where the tape goes, and how to keep it comparable. */
export function MeasureHelpSheet({ onClose }: { onClose: () => void }) {
  const t = useTranslations("Body");
  const labelId = useId();
  return (
    <Sheet labelId={labelId} title={t("helpTitle")} onClose={onClose} footer={<SheetButton primary onClick={onClose}>{t("close")}</SheetButton>}>
      <div className="flex flex-col gap-3 text-sm" style={{ color: "var(--text-soft)" }}>
        <p>{t("helpIntro")}</p>
        <dl className="flex flex-col gap-2">
          {HELP.map((item) => (
            <div key={item}>
              <dt className="font-bold" style={{ color: "var(--text)" }}>{t(key("metric", item))}</dt>
              <dd>{t(key("help", item))}</dd>
            </div>
          ))}
        </dl>
        <p>{t("helpPhotos")}</p>
      </div>
    </Sheet>
  );
}

"use client";

import { useId, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { confirmDeviceImport, type DeviceActivityCandidate, type DevicePendingImport } from "@/api/devices";
import { formatTime } from "@/components/client/format";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { deviceErrorCode, deviceErrorKey } from "@/components/devices/DeviceBits";
import { formatDuration, sportIcon } from "@/components/devices/garmin-model";

const SEPARATE = "separate";

/**
 * «Ήταν αυτό το CrossFit 18:00;» (board 16 Q2 A): a watch workout that could
 * be more than one class or workout waits for the member, one at a time.
 * Choosing a candidate merges it there; «Ξεχωριστή προπόνηση» keeps it apart.
 */
export function DevicePendingSheet({
  token,
  imports,
  locale,
  onClose,
  onAnswered,
}: {
  token: string;
  imports: DevicePendingImport[];
  locale: string;
  onClose: () => void;
  onAnswered: () => void;
}) {
  const [index, setIndex] = useState(0);
  const current = imports[index];
  if (!current) return null;
  return (
    <PendingQuestion
      key={current.id}
      token={token}
      pending={current}
      locale={locale}
      position={imports.length > 1 ? { at: index + 1, of: imports.length } : null}
      onClose={onClose}
      onAnswered={() => {
        onAnswered();
        if (index + 1 < imports.length) setIndex(index + 1);
        else onClose();
      }}
    />
  );
}

function PendingQuestion({
  token,
  pending,
  locale,
  position,
  onClose,
  onAnswered,
}: {
  token: string;
  pending: DevicePendingImport;
  locale: string;
  position: { at: number; of: number } | null;
  onClose: () => void;
  onAnswered: () => void;
}) {
  const t = useTranslations("Devices");
  const labelId = useId();
  const groupId = useId();
  const activity = pending.activity;
  const candidates = activity.candidates ?? [];
  const [choice, setChoice] = useState<string>(candidates[0]?.id ?? SEPARATE);
  const label = (candidate: DeviceActivityCandidate) =>
    [candidate.title || t(["candidate", candidate.kind].join("_")), formatTime(candidate.starts_at, locale)].join(" ");
  const answer = useMutation({
    mutationFn: () => confirmDeviceImport(token, pending.id, choice === SEPARATE ? { as_new: true } : { target_id: choice }),
    onSuccess: onAnswered,
    onError: (error) => {
      // Someone (another tab) already answered: move on.
      if (deviceErrorCode(error) === "import_already_settled") onAnswered();
    },
  });
  const first = candidates[0];

  return (
    <Sheet
      title={first ? t("pendingQuestion", { title: label(first) }) : t("pendingTitle")}
      eyebrow={position ? t("pendingPosition", position) : t("pendingTitle")}
      labelId={labelId}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("later")}</SheetButton>
          <SheetButton primary disabled={answer.isPending} onClick={() => answer.mutate()}>
            {t("confirm")}
          </SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-4" data-testid="device-pending-sheet">
        <p className="flex items-center gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
          <span aria-hidden="true">{sportIcon(activity.sport)}</span>
          {t("pendingIntro", { title: activity.title, time: formatTime(activity.started_at, locale), duration: formatDuration(activity.duration_seconds) })}
        </p>
        <div role="radiogroup" aria-labelledby={groupId} className="flex flex-col gap-2">
          <span id={groupId} className="sr-only">{t("pendingTitle")}</span>
          {candidates.map((candidate) => (
            <ChoicePill key={candidate.id} selected={choice === candidate.id} onSelect={() => setChoice(candidate.id)} hint={t(["candidate", candidate.kind].join("_"))}>
              {label(candidate)}
            </ChoicePill>
          ))}
          <ChoicePill selected={choice === SEPARATE} onSelect={() => setChoice(SEPARATE)} hint={t("separateHint")}>
            {t("separate")}
          </ChoicePill>
        </div>
        <ErrorLine message={answer.isError && deviceErrorCode(answer.error) !== "import_already_settled" ? t(deviceErrorKey(answer.error)) : null} />
      </div>
    </Sheet>
  );
}

"use client";

import { useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import type { PRRecord } from "@/api/gamification";
import { gymClubFor } from "@/components/community/community";
import { ComposeSheet } from "@/components/community/ComposeSheet";
import { Sheet, SheetButton } from "@/components/community/Sheet";
import { useMyClubs } from "@/components/community/use-community";
import { formatScore } from "@/components/pantheon/PantheonCard";

/**
 * After a PR is logged (ADR-157 §8): «Νέο PR!» with «Μοιράσου το», which
 * opens compose with the PR attached, the media picker first and the box's
 * club as the audience. Nothing posts until «Δημοσίευση».
 */
export function PRShareFlow({
  children,
  onClose,
}: {
  children: (onSaved: (pr: PRRecord) => void) => ReactNode;
  onClose: () => void;
}) {
  const [saved, setSaved] = useState<PRRecord | null>(null);
  const [sharing, setSharing] = useState(false);
  if (saved && sharing) return <SharePRCompose pr={saved} onClose={onClose} />;
  if (saved) return <PRLoggedSheet pr={saved} onShare={() => setSharing(true)} onClose={onClose} />;
  return <>{children(setSaved)}</>;
}

function PRLoggedSheet({ pr, onShare, onClose }: { pr: PRRecord; onShare: () => void; onClose: () => void }) {
  const t = useTranslations("Media");
  return (
    <Sheet
      labelId="pr-logged"
      title={t("prSavedTitle")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("prNotNow")}</SheetButton>
          <SheetButton primary onClick={onShare}>{t("prShare")}</SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-2">
        <p className="text-lg font-bold" style={{ color: "var(--text)" }}>
          {pr.name} · <span className="tabular-nums">{formatScore(Number(pr.current_score), pr.unit)}</span>
        </p>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("prSavedBody")}</p>
      </div>
    </Sheet>
  );
}

function SharePRCompose({ pr, onClose }: { pr: PRRecord; onClose: () => void }) {
  const clubs = useMyClubs();
  if (!clubs.isSuccess && !clubs.isError) return null;
  const list = clubs.data ?? [];
  const club = gymClubFor(list, pr.organization_id ?? null);
  return <ComposeSheet clubs={list} clubId={club?.id ?? null} initialAttachment={{ type: "pr", id: pr.id }} onClose={onClose} />;
}

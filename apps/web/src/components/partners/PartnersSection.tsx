"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { PARTNERS_KEY, putPartnerProfile } from "@/api/partners";
import { ErrorLine } from "@/components/community/Sheet";
import { HubCard } from "@/components/member-app/HubParts";
import { useUiTranslations } from "@/i18n/ui";

import { PartnerDeck } from "./PartnerDeck";
import { PartnerProfileSheet } from "./PartnerProfileSheet";
import { partnerErrorMessage } from "./errors";
import { partnersStage } from "./partners-model";
import { usePartnersClub, usePartnersToken } from "./use-partners";

/**
 * Club › Μέλη › Partners (ADR-169, brief §7.3): a training partner among this
 * club's members. Nothing shows where the gym hasn't offered it. Before you
 * opt in it is one short card; after, the deck. The safety line stays under
 * it: members only, both must agree, report or block at any time.
 */
export function PartnersSection({ clubId }: { clubId: string }) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const overview = usePartnersClub(clubId);
  const [editing, setEditing] = useState(false);
  const stage = partnersStage(overview.data);

  const resume = useMutation({
    mutationFn: () => putPartnerProfile(token!, clubId, { active: true }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: PARTNERS_KEY }),
  });

  if (stage === "hidden" || !overview.data) return null;
  const data = overview.data;

  return (
    <HubCard eyebrow={t("title")} highlighted={stage === "intro"}>
      <div className="flex flex-col gap-3" data-testid="partners-section">
        {stage === "intro" ? (
          <>
            <h2 className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("introTitle")}</h2>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("introBody")}</p>
            <PrimaryButton onClick={() => setEditing(true)}>{t("introStart")}</PrimaryButton>
          </>
        ) : stage === "suspended" ? (
          <p className="text-sm" role="note" style={{ color: "var(--text-soft)" }}>{t("suspended")}</p>
        ) : stage === "paused" ? (
          <>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("paused")}</p>
            <div className="flex gap-2">
              <PrimaryButton onClick={() => resume.mutate()} disabled={resume.isPending}>{t("resume")}</PrimaryButton>
              <TextButton onClick={() => setEditing(true)}>{t("editProfile")}</TextButton>
            </div>
            <ErrorLine message={partnerErrorMessage(resume.error, t, tUi)} />
          </>
        ) : (
          <>
            <PartnerDeck clubId={clubId} options={data.options} swipesRemaining={data.swipes_remaining} distance={data.distance} />
            <TextButton onClick={() => setEditing(true)}>{t("editProfile")}</TextButton>
          </>
        )}
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("safetyLine")}</p>
      </div>
      {editing ? <PartnerProfileSheet clubId={clubId} overview={data} onClose={() => setEditing(false)} /> : null}
    </HubCard>
  );
}

function PrimaryButton({ onClick, disabled, children }: { onClick: () => void; disabled?: boolean; children: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
      style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
    >
      {children}
    </button>
  );
}

function TextButton({ onClick, children }: { onClick: () => void; children: string }) {
  return (
    <button type="button" onClick={onClick} className="min-h-11 self-start text-sm font-semibold" style={{ color: "var(--primary)" }}>
      {children}
    </button>
  );
}

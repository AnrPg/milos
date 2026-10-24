"use client";

import { useState } from "react";

import type { ChallengeRecord } from "@/api/landing";
import { HelpIcon, InfoModal } from "@/components/InfoModal";
import { ChallengeCard } from "@/components/workouts/ChallengeCard";
import { useUiTranslations } from "@/i18n/ui";

/**
 * The gym's live seasonal challenges. In Phase 1 this slot becomes the
 * club's #challenges channel card (ADR-138, M8); until then it reads the
 * landing payload. Hidden while there are none (ANR 2026-10-24).
 */
export function ChallengesCard({ challenges }: { challenges: ChallengeRecord[] }) {
  const i18n = useUiTranslations();
  const [activeInfoModal, setActiveInfoModal] = useState<"challenges" | null>(null);
  if (challenges.length === 0) return null;

  return (
    <section id="challenges" className="rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{i18n("challengesff38765")}</p>
            <HelpIcon tooltip={i18n("whatAreChallengesfdf13a8")} onClick={() => setActiveInfoModal("challenges")} />
          </div>
          <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{i18n("seasonalMomentum8724e0a")}</h2>
        </div>
      </div>
      <div className="mt-5 space-y-4">
        {challenges.map((challenge) => (
          <ChallengeCard key={challenge.id} challenge={challenge} />
        ))}
      </div>
      {activeInfoModal === "challenges" ? (
        <InfoModal title={i18n("seasonalChallengesfd69ec6")} onClose={() => setActiveInfoModal(null)}>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("whatTheyAree294e57")}</strong> {i18n("timeLimitedGoalsSetByYourCoachOreba26f4")}
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("howToParticipate3af38ca")}</strong> {i18n("challengesStartAutomaticallyWhenTheyGoLiveJust0dca263")}
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("rewards9f52f32")}</strong> {i18n("completingAChallengeEarnsYouABadgeDisplayedd966d03")}
          </p>
        </InfoModal>
      ) : null}
    </section>
  );
}

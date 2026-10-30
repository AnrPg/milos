"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useState } from "react";
import { useMutation } from "@tanstack/react-query";

import { reportInjury, type ReportInjuryRequest } from "@/api/wellbeing";
import { useSession } from "@/components/session-provider";
import { InjuryShareField } from "@/components/member-app/wellbeing/InjurySharing";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

export function WellbeingFormPanel({ onClose }: { onClose: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const [bodyArea, setBodyArea] = useState("");
  const [severity, setSeverity] = useState<ReportInjuryRequest["severity"]>("mild");
  const [limitations, setLimitations] = useState("");
  // ADR-286: «Να το δει το box μου», on unless the member turns it off.
  const [shareWithBox, setShareWithBox] = useState(true);
  const [submitted, setSubmitted] = useState(false);

  const reportMutation = useMutation({
    mutationFn: async () =>
      reportInjury(tokens!.access_token, {
        body_area: bodyArea,
        severity,
        training_limitations: limitations,
        shared_with_box: shareWithBox,
      }),
    onSuccess: () => {
      setBodyArea("");
      setLimitations("");
      setSubmitted(true);
    },
  });

  return (
    <Dialog
      onClose={onClose}
      variant="drawer"
      layer="drawer"
      size="full"
      panelClassName="md:max-w-[380px]"
      eyebrow={i18n("trainingReadiness9672bfd")}
      description={i18n("reportDiscomfortOrLimitations5e07927")}
      ariaLabel={i18n("trainingReadiness9672bfd")}
    >
        {submitted ? (
          <div className="py-8 text-center">
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
              {i18n("submittedThankYoud1876c0")}
            </p>
            <button
              type="button"
              className="mt-4 text-sm"
              style={{ color: "var(--primary)" }}
              onClick={() => setSubmitted(false)}
            >
              {i18n("reportAnothere0c66a7")}
            </button>
          </div>
        ) : (
          <form
            className="space-y-4"
            onSubmit={(e) => {
              e.preventDefault();
              reportMutation.mutate();
            }}
          >
            <div>
              <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--muted)" }}>
                {i18n("bodyAreaa785bb3")}
              </label>
              <input
                className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                }}
                placeholder={i18n("eGRightShouldercaf6c58")}
                required
                value={bodyArea}
                onChange={(e) => setBodyArea(e.target.value)}
              />
            </div>

            <div>
              <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--muted)" }}>
                {i18n("severityde314fa")}
              </label>
              <Select
                className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                }}
                value={severity}
                onValueChange={(value) =>
                  setSeverity(value as ReportInjuryRequest["severity"])
                }
              >
                <option value="mild">{i18n("mildCanTrainWithCare8b2bbe3")}</option>
                <option value="moderate">{i18n("moderateLimitedTraining5358133")}</option>
                <option value="severe">{i18n("severeCannotTrainf98a85c")}</option>
              </Select>
            </div>

            <div>
              <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--muted)" }}>
                {i18n("trainingLimitationsOptional201e2b9")}
              </label>
              <textarea
                className="w-full rounded-xl px-3 py-2.5 text-sm outline-none resize-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                  minHeight: "80px",
                }}
                placeholder={i18n("describeWhatMovementsHurtOrAreNotPossiblef5b6d6e")}
                value={limitations}
                onChange={(e) => setLimitations(e.target.value)}
              />
            </div>

            <InjuryShareField checked={shareWithBox} onChange={setShareWithBox} />

            {reportMutation.error instanceof Error && (
              <ErrorNotice>
                {localizeError(reportMutation.error, i18n)}
              </ErrorNotice>
            )}

            <button
              type="submit"
              disabled={reportMutation.isPending || !bodyArea.trim()}
              className="w-full rounded-xl py-2.5 text-sm font-semibold"
              style={{
                background: "var(--primary)",
                color: "var(--primary-contrast)",
                opacity: reportMutation.isPending || !bodyArea.trim() ? 0.5 : 1,
              }}
            >
              {reportMutation.isPending ? i18n("reportingadbd903") : i18n("submitReporta668129")}
            </button>
          </form>
        )}
    </Dialog>
  );
}

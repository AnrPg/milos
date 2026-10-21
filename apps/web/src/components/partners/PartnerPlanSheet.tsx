"use client";

import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { fetchPartnerSessions, partnerSessionsKey, suggestPartnerPlan, type PartnerSession } from "@/api/partners";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { useUiTranslations } from "@/i18n/ui";

import { PartnerTag } from "./PartnerBits";
import { partnerErrorMessage } from "./errors";
import { usePartnersToken } from "./use-partners";

/**
 * «Κλείστε μαζί» (ADR-169 §8): the gym's next classes that suit you both,
 * those either of you booked first, then the ones in a time you both chose.
 * Picking one posts it in the conversation, with a short note if you like;
 * each of you books it yourself from the class sheet.
 */
export function PartnerPlanSheet({
  matchId,
  name,
  onClose,
  onPlanned,
}: {
  matchId: string;
  name: string;
  onClose: () => void;
  onPlanned: () => void;
}) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const format = useFormatter();
  const token = usePartnersToken();
  const [picked, setPicked] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const sessions = useQuery({
    queryKey: partnerSessionsKey(matchId),
    enabled: Boolean(token),
    queryFn: () => fetchPartnerSessions(token!, matchId),
  });
  const send = useMutation({
    mutationFn: (classId: string) => suggestPartnerPlan(token!, matchId, classId, note.trim() || null),
    onSuccess: () => {
      onPlanned();
      onClose();
    },
  });
  const rows = sessions.data?.sessions ?? [];
  const when = (session: PartnerSession) =>
    format.dateTime(new Date(session.scheduled_at), {
      weekday: "short",
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: sessions.data?.timezone ?? undefined,
    });

  return (
    <Sheet
      labelId={`partner-plan-${matchId}`}
      eyebrow={t("planEyebrow")}
      title={t("planTitle", { name })}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary disabled={!picked || send.isPending} onClick={() => picked && send.mutate(picked)}>
            {send.isPending ? t("sending") : t("planSend")}
          </SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {sessions.isPending ? (
          <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : rows.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("planEmpty")}</p>
        ) : (
          <div role="radiogroup" aria-label={t("planTitle", { name })} className="flex flex-col gap-2" data-testid="partner-sessions">
            {rows.map((session) => (
              <button
                key={session.class_id}
                type="button"
                role="radio"
                aria-checked={picked === session.class_id}
                onClick={() => setPicked(session.class_id)}
                className="flex flex-col items-start gap-1 rounded-2xl px-4 py-3 text-start"
                style={{
                  background: picked === session.class_id ? "color-mix(in srgb, var(--primary) 14%, var(--panel))" : "var(--panel-raised)",
                  border: `1px solid ${picked === session.class_id ? "var(--primary)" : "var(--border)"}`,
                  color: "var(--text)",
                }}
              >
                <span className="text-sm font-bold">{session.name ?? t("planClass")}</span>
                <span className="text-sm" style={{ color: "var(--text-soft)" }}>{when(session)}</span>
                <span className="flex flex-wrap gap-1.5">
                  {session.booked_by_me ? <PartnerTag strong>{t("bookedByMe")}</PartnerTag> : null}
                  {session.booked_by_partner ? <PartnerTag strong>{t("bookedByPartner", { name })}</PartnerTag> : null}
                  {session.shared_time ? <PartnerTag>{t("sharedTime")}</PartnerTag> : null}
                  {!session.booked_by_me ? <PartnerTag>{t("spotsLeft", { count: session.spots_remaining })}</PartnerTag> : null}
                </span>
              </button>
            ))}
          </div>
        )}
        {rows.length > 0 ? (
          <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("planNote")}
            <input
              value={note}
              maxLength={280}
              onChange={(event) => setNote(event.target.value)}
              placeholder={t("planNotePlaceholder")}
              className="min-h-11 rounded-2xl px-3 text-sm font-normal"
              style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </label>
        ) : null}
        <ErrorLine message={partnerErrorMessage(sessions.error ?? send.error, t, tUi)} />
      </div>
    </Sheet>
  );
}

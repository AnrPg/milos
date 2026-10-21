"use client";

import Link from "next/link";
import { useState } from "react";
import { useTranslations } from "next-intl";

import type { SupportRequest } from "@/api/buddies";
import { ErrorLine } from "@/components/community/Sheet";
import { useUiTranslations } from "@/i18n/ui";

import { BreathingTimer } from "./BreathingTimer";
import { personName, replyText, senderPhase, undoSecondsLeft } from "./buddy-model";
import { buddyErrorMessage } from "./errors";
import { useNow, useSendSupport, useSupportRequest } from "./use-buddies";

/**
 * What the sender sees after «Χρειάζομαι στήριξη»: the undo for five
 * seconds, who received it and who has quiet hours, who replied (with the
 * way into the conversation), and after ten minutes with no reply the calm
 * card. Polls while it waits.
 */
export function SupportStatus({ request: initial, onResent }: { request: SupportRequest; onResent?: (request: SupportRequest) => void }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const query = useSupportRequest(initial.id, initial);
  const request = query.data ?? initial;
  const { undo } = useSendSupport();
  const ticking = request.status === "sending";
  const now = useNow(ticking || request.status === "delivered", ticking ? 250 : 15_000);
  const phase = senderPhase(request, now);
  const left = undoSecondsLeft(request.undo_until, now);
  const recipients = request.recipients ?? [];
  const names = recipients.map((recipient) => personName(recipient.person, t("someone"))).join(", ");

  if (phase === "undone") {
    return (
      <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }} data-testid="support-status">
        {t("undone")}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-3" data-testid="support-status">
      {phase === "sending" ? (
        <div className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)" }} role="status">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("sendingIn", { seconds: left })}</span>
          <button
            type="button"
            onClick={() => undo.mutate(request.id)}
            disabled={undo.isPending}
            className="min-h-9 rounded-full px-3 text-sm font-bold disabled:opacity-50"
            style={{ color: "var(--primary)" }}
          >
            {t("undo")}
          </button>
        </div>
      ) : (
        <p role="status" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {names ? t("sentTo", { names }) : t("sent")}
        </p>
      )}
      <ErrorLine message={buddyErrorMessage(undo.error, t, tUi)} />

      {request.message ? (
        <p className="rounded-2xl px-4 py-2 text-sm" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>«{request.message}»</p>
      ) : null}

      {recipients.length > 0 ? (
        <ul className="flex flex-col gap-1 text-sm" data-testid="support-recipient-status">
          {recipients.map((recipient, index) => {
            const name = personName(recipient.person, t("someone"));
            return (
              <li key={recipient.person?.id ?? index} style={{ color: "var(--text-soft)" }}>
                {recipient.replied_at ? t("recipientReplied", { name }) : recipient.quiet_hours ? t("recipientQuiet", { name }) : t("recipientWaiting", { name })}
              </li>
            );
          })}
        </ul>
      ) : null}

      {(request.replies?.length ?? 0) > 0 ? (
        <ul className="flex flex-col gap-2" data-testid="support-replies">
          {request.replies!.map((reply) => (
            <li key={reply.id} className="flex flex-col gap-1 rounded-2xl px-4 py-3" style={{ background: "color-mix(in srgb, var(--primary) 10%, var(--panel))" }}>
              <span className="text-sm" style={{ color: "var(--text)" }}>
                <b>{personName(reply.person, t("someone"))}:</b> {replyText(reply, t)}
              </span>
              {reply.conversation?.link_id ? (
                <Link href={`/me/buddy/${encodeURIComponent(reply.conversation.link_id)}/chat`} className="text-sm font-bold" style={{ color: "var(--primary)" }}>
                  {t("openChat")}
                </Link>
              ) : null}
            </li>
          ))}
        </ul>
      ) : null}

      {phase === "noReply" ? <NoReplyCard request={request} onResent={onResent} /> : null}
    </div>
  );
}

/**
 * The calm card ten minutes after a request nobody answered (board 15 q5 A):
 * breathing for two minutes, a glass of water, a short walk, «Στείλε ξανά»,
 * and a line to help lines, as information, never advice.
 */
export function NoReplyCard({ request, onResent }: { request: SupportRequest; onResent?: (request: SupportRequest) => void }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const { send } = useSendSupport();
  const [breathing, setBreathing] = useState(false);
  const [done, setDone] = useState<string[]>([]);
  const nudge = request.nudge;
  const mark = (item: string) => setDone((current) => (current.includes(item) ? current : [...current, item]));
  const canResend = nudge?.can_resend !== false;

  return (
    <section
      aria-labelledby={`no-reply-${request.id}`}
      className="flex flex-col gap-3 rounded-2xl p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", borderInlineStart: "3px solid var(--primary)" }}
      data-testid="no-reply-card"
    >
      <h3 id={`no-reply-${request.id}`} className="text-base font-bold" style={{ color: "var(--text)" }}>{t("noReplyTitle")}</h3>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("noReplyLead")}</p>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          aria-expanded={breathing}
          onClick={() => setBreathing(!breathing)}
          className="min-h-9 rounded-full px-3 text-sm font-semibold"
          style={{ background: breathing ? "var(--primary)" : "var(--panel-raised)", color: breathing ? "var(--primary-contrast)" : "var(--text)", border: "1px solid var(--border)" }}
        >
          {t("tryBreathing")}
        </button>
        <button
          type="button"
          aria-pressed={done.includes("water")}
          onClick={() => mark("water")}
          className="min-h-9 rounded-full px-3 text-sm font-semibold"
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {done.includes("water") ? t("tryWaterDone") : t("tryWater")}
        </button>
        <button
          type="button"
          aria-pressed={done.includes("walk")}
          onClick={() => mark("walk")}
          className="min-h-9 rounded-full px-3 text-sm font-semibold"
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {done.includes("walk") ? t("tryWalkDone") : t("tryWalk")}
        </button>
      </div>
      {breathing ? <BreathingTimer seconds={nudge?.breathing_seconds ?? undefined} /> : null}
      {canResend ? (
        <div>
          <button
            type="button"
            disabled={send.isPending}
            onClick={() => send.mutate(request.message ?? null, { onSuccess: (next) => onResent?.(next) })}
            className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("sendAgain")}
          </button>
        </div>
      ) : null}
      <ErrorLine message={buddyErrorMessage(send.error, t, tUi)} />
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {t("helpLinesLead")}{" "}
        <Link href="/help/support-lines" className="font-semibold underline" style={{ color: "var(--text-soft)" }}>
          {t("helpLinesLink")}
        </Link>
      </p>
    </section>
  );
}

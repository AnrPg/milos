"use client";

import Link from "next/link";
import { useFormatter, useLocale, useTranslations } from "next-intl";
import type { ReactNode } from "react";

import type { PersonConversation } from "@/api/conversations";
import { PersonAvatar } from "@/components/social/PersonAvatar";

import { personLabel, previewLine } from "./conversation-model";
import { conversationHref } from "./use-conversations";
import { withClock } from "@/lib/clock";

/** «Buddy»: you and they follow each other (ADR-193 §1). */
export function BuddyBadge() {
  const t = useTranslations("Conversations");
  return (
    <span
      className="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold"
      style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", color: "var(--text)" }}
      data-testid="conversation-buddy"
    >
      {t("buddy")}
    </span>
  );
}

function sameDay(a: Date, b: Date) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/** Today's messages by their time, older ones by their day. */
export function useShortTime() {
  const format = useFormatter();
  const locale = useLocale();
  return (iso: string | null | undefined) => {
    if (!iso) return "";
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return "";
    return sameDay(date, new Date())
      ? format.dateTime(date, withClock(locale, { hour: "2-digit", minute: "2-digit" }))
      : format.dateTime(date, { day: "numeric", month: "short" });
  };
}

/** The person, the Buddy badge, the last message and the time, on one card's worth of row. */
function RowBody({ conversation }: { conversation: PersonConversation }) {
  const t = useTranslations("Conversations");
  const time = useShortTime();
  const name = personLabel(conversation.person, t("someone"));
  const last = conversation.last_message;
  const preview = last ? previewLine(last.body) : "";
  return (
    <span className="flex min-w-0 flex-1 items-center gap-3">
      <PersonAvatar name={name} url={conversation.person.avatar_url} size={44} />
      <span className="min-w-0 flex-1">
        <span className="flex min-w-0 items-center gap-2">
          <span
            className="truncate text-sm"
            style={{ color: "var(--text)", fontWeight: conversation.unread ? 800 : 600 }}
          >
            {name}
          </span>
          {conversation.buddy ? <BuddyBadge /> : null}
        </span>
        <span className="flex min-w-0 items-center gap-1.5 text-xs" style={{ color: conversation.unread ? "var(--text-soft)" : "var(--dim)" }}>
          <span className="truncate">{last?.mine ? t("you", { text: preview }) : preview}</span>
          {last ? (
            <span className="shrink-0" aria-hidden="true">
              · {time(last.created_at)}
            </span>
          ) : null}
        </span>
      </span>
    </span>
  );
}

function UnreadDot({ show }: { show: boolean }) {
  const t = useTranslations("Conversations");
  if (!show) return null;
  return (
    <span
      role="img"
      aria-label={t("unread")}
      className="h-2.5 w-2.5 shrink-0 rounded-full"
      style={{ background: "var(--primary)" }}
      data-testid="conversation-unread"
    />
  );
}

/** One inbox conversation, linking to it. */
export function ConversationRow({ conversation, onNavigate }: { conversation: PersonConversation; onNavigate?: () => void }) {
  return (
    <Link
      href={conversationHref(conversation.id)}
      onClick={onNavigate}
      className="flex min-h-14 items-center gap-3 rounded-2xl px-3 py-2 outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)]"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="conversation-row"
    >
      <RowBody conversation={conversation} />
      <UnreadDot show={conversation.unread} />
    </Link>
  );
}

/**
 * One message request: the row opens it, and Accept or Decline answer it
 * from the list (Instagram-style). Declining hides it for good; the sender
 * is not told.
 */
export function RequestRow({
  conversation,
  onNavigate,
  onAccept,
  onDecline,
  busy = false,
}: {
  conversation: PersonConversation;
  onNavigate?: () => void;
  onAccept: () => void;
  onDecline: () => void;
  busy?: boolean;
}) {
  return (
    <div
      className="flex flex-col gap-2 rounded-2xl px-3 py-2"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="conversation-request"
    >
      <Link
        href={conversationHref(conversation.id)}
        onClick={onNavigate}
        className="flex min-h-12 min-w-0 items-center gap-3 rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)]"
      >
        <RowBody conversation={conversation} />
        <UnreadDot show={conversation.unread} />
      </Link>
      <RequestButtons onAccept={onAccept} onDecline={onDecline} busy={busy} />
    </div>
  );
}

/** Accept · Decline, side by side, for a request's row and its banner. */
export function RequestButtons({ onAccept, onDecline, busy }: { onAccept: () => void; onDecline: () => void; busy?: boolean }) {
  const t = useTranslations("Conversations");
  return (
    <div className="flex gap-2">
      <ActionButton onClick={onDecline} disabled={busy}>
        {t("decline")}
      </ActionButton>
      <ActionButton primary onClick={onAccept} disabled={busy}>
        {t("accept")}
      </ActionButton>
    </div>
  );
}

function ActionButton({
  primary = false,
  disabled,
  onClick,
  children,
}: {
  primary?: boolean;
  disabled?: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
      style={
        primary
          ? { background: "var(--primary)", color: "var(--primary-contrast)" }
          : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }
      }
    >
      {children}
    </button>
  );
}

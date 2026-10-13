"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";

import { fetchReplyQueue } from "@/api/staff";
import { useSession } from "@/components/session-provider";
import { chatThreadHref, replyUrgency, sortReplyQueue, staffErrorMessage } from "@/components/staff/staff-helpers";
import { Pill, secondaryButtonClass, secondaryButtonStyle, StaffPanel, StatusText } from "@/components/staff/staff-ui";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

export function ReplyQueue() {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens } = useSession();

  const query = useQuery({
    queryKey: ["staff", "reply-queue"],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchReplyQueue(tokens!.access_token),
    refetchInterval: 60_000,
  });

  const items = sortReplyQueue(query.data ?? []);
  const now = new Date();
  const when = (iso: string) =>
    new Intl.DateTimeFormat(uiLocale, { dateStyle: "medium", timeStyle: "short" }).format(new Date(iso));

  return (
    <StaffPanel eyebrow={i18n("stfReplyQueueEyebrow")} labelledBy="staff-reply-queue" title={i18n("stfReplyQueueTitle")}>
      {query.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : query.isError ? (
        <StatusText tone="error">{staffErrorMessage(query.error, i18n)}</StatusText>
      ) : items.length === 0 ? (
        <StatusText tone="muted">{i18n("stfReplyQueueEmpty")}</StatusText>
      ) : (
        <ul className="space-y-2">
          {items.map((item) => {
            const urgency = replyUrgency(item, now);
            return (
              <li
                key={item.message_id}
                className="flex flex-wrap items-center justify-between gap-3 rounded-[1.2rem] px-4 py-3"
                style={{
                  background:
                    urgency === "overdue" ? "color-mix(in srgb, var(--danger) 8%, transparent)" : "var(--panel-muted)",
                  border:
                    urgency === "overdue"
                      ? "1px solid color-mix(in srgb, var(--danger) 30%, transparent)"
                      : "1px solid var(--border)",
                }}
              >
                <div className="min-w-0">
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {item.client_nickname ?? i18n("stfUnknownMember")}
                  </p>
                  <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
                    {i18n("stfMessageSentAt", { time: when(item.sent_at) })}
                    {item.due_at ? ` · ${i18n("stfReplyDueAt", { time: when(item.due_at) })}` : ""}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  {urgency === "overdue" ? (
                    <Pill tone="danger">{i18n("stfOverdue")}</Pill>
                  ) : urgency === "due_soon" ? (
                    <Pill tone="warning">{i18n("stfDueSoon")}</Pill>
                  ) : null}
                  <Link className={secondaryButtonClass} href={chatThreadHref(item.thread_id)} style={secondaryButtonStyle}>
                    {i18n("stfOpenThread")}
                  </Link>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </StaffPanel>
  );
}

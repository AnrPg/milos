"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BOX_CONVERSATIONS_KEY, fetchBoxConversations } from "@/api/trials";

/** Conversations with boxes you're not a member of (board 6 Q6), above your chats. */
export function BoxConversationsList({ token }: { token: string | null }) {
  const t = useTranslations("Trials");
  const conversations = useQuery({
    queryKey: BOX_CONVERSATIONS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchBoxConversations(token!),
  });
  const rows = conversations.data ?? [];
  if (rows.length === 0) return null;
  return (
    <section aria-label={t("boxChats")} className="border-b" style={{ borderColor: "var(--border)" }}>
      <p className="px-4 pt-3 text-[11px] font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("boxChats")}</p>
      {rows.map((row) => (
        <Link key={row.thread_id} href={`/b/${row.box.slug}/chat`} className="flex items-center gap-3 px-4 py-3">
          <span
            aria-hidden="true"
            className="grid h-8 w-8 shrink-0 place-items-center rounded-full text-xs font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {row.box.name[0]?.toUpperCase()}
          </span>
          <span className="flex min-w-0 flex-1 flex-col">
            <span className="truncate text-sm font-medium" style={{ color: "var(--text)" }}>{row.box.name}</span>
            {row.last_message ? (
              <span className="truncate text-xs" style={{ color: "var(--dim)" }}>{row.last_message.body}</span>
            ) : null}
          </span>
          {row.unread ? <span aria-label={t("unread")} className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: "var(--primary)" }} /> : null}
        </Link>
      ))}
    </section>
  );
}

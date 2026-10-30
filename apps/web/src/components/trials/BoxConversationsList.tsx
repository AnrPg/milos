"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BOX_CONVERSATIONS_KEY, fetchBoxConversations } from "@/api/trials";
import { useMyProviders } from "@/components/providers/use-providers";

import { boxChatHref } from "./box-chat-links";
import { boxesToWrite } from "./box-conversations-model";

/**
 * Your conversations with boxes, in Μηνύματα › Box (board 6 Q6, ADR-282):
 * the boxes you belong to and the ones you wrote to, latest first, then
 * «Γράψε στο …» for each of your boxes you have not written to yet.
 */
export function BoxConversationsList({ token, onNavigate }: { token: string | null; onNavigate?: () => void }) {
  const t = useTranslations("Trials");
  const conversations = useQuery({
    queryKey: BOX_CONVERSATIONS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchBoxConversations(token!),
  });
  const providers = useMyProviders();
  const rows = conversations.data ?? [];
  const toWrite = conversations.isSuccess ? boxesToWrite(providers.data?.providers ?? [], rows) : [];
  if (rows.length === 0 && toWrite.length === 0) return null;
  return (
    <section aria-label={t("boxChats")} className="border-b" style={{ borderColor: "var(--border)" }}>
      <p className="px-4 pt-3 text-[11px] font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("boxChats")}</p>
      {rows.map((row) => (
        <Link key={row.thread_id} href={boxChatHref(row.box.slug)} onClick={onNavigate} className="flex items-center gap-3 px-4 py-3">
          <BoxMark name={row.box.name} />
          <span className="flex min-w-0 flex-1 flex-col">
            <span className="truncate text-sm font-medium" style={{ color: "var(--text)" }}>{row.box.name}</span>
            {row.last_message ? (
              <span className="truncate text-xs" style={{ color: "var(--dim)" }}>{row.last_message.body}</span>
            ) : null}
          </span>
          {row.unread ? <span aria-label={t("unread")} className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: "var(--primary)" }} /> : null}
        </Link>
      ))}
      {toWrite.map((box) => (
        <Link
          key={box.slug}
          href={boxChatHref(box.slug)}
          onClick={onNavigate}
          className="flex items-center gap-3 px-4 py-3"
          data-testid="write-to-box"
        >
          <BoxMark name={box.name} />
          <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--primary)" }}>
            {t("writeToBox", { box: box.name })}
          </span>
        </Link>
      ))}
    </section>
  );
}

function BoxMark({ name }: { name: string }) {
  return (
    <span
      aria-hidden="true"
      className="grid h-8 w-8 shrink-0 place-items-center rounded-full text-xs font-bold"
      style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
    >
      {name[0]?.toUpperCase()}
    </span>
  );
}

"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { ConversationFolder } from "@/api/conversations";
import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";

import { ConversationRow, RequestRow } from "./ConversationRow";
import { listedConversations } from "./conversation-model";
import { REQUESTS_HREF, useConversationList, useRequestActions } from "./use-conversations";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * The body of a folder (ADR-193 §3): inbox rows, or requests with Accept
 * and Decline, latest first, with «Show more» for older ones. No page
 * chrome, so any inbox can embed it. `hideWhenEmpty` renders nothing for an
 * empty folder (vision §4 principle 2) instead of the quiet empty line.
 */
export function ConversationList({
  folder,
  onNavigate,
  hideWhenEmpty = false,
}: {
  folder: ConversationFolder;
  onNavigate?: () => void;
  hideWhenEmpty?: boolean;
}) {
  const t = useTranslations("Conversations");
  const tUi = useUiTranslations();
  const pages = useConversationList(folder);
  const { accept, decline } = useRequestActions();
  const rows = listedConversations(pages.data?.pages ?? []);
  const actionError = accept.error ?? decline.error;

  if (pages.isPending) {
    return hideWhenEmpty ? null : (
      <p className="px-1 text-sm" role="status" style={{ color: "var(--dim)" }}>
        {t("loading")}
      </p>
    );
  }
  if (pages.isError) {
    return hideWhenEmpty ? null : (
      <ErrorNotice className="px-1">
        {localizeError(pages.error, tUi)}
      </ErrorNotice>
    );
  }
  if (rows.length === 0) {
    return hideWhenEmpty ? null : (
      <p className="px-1 py-4 text-center text-sm" style={{ color: "var(--dim)" }} data-testid="conversations-empty">
        {folder === "requests" ? t("emptyRequests") : t("emptyInbox")}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-2" data-testid={`conversations-${folder}`}>
      {actionError ? (
        <ErrorNotice className="px-1">
          {localizeError(actionError, tUi)}
        </ErrorNotice>
      ) : null}
      <ul className="flex flex-col gap-2">
        {rows.map((conversation) => (
          <li key={conversation.id}>
            {folder === "requests" ? (
              <RequestRow
                conversation={conversation}
                onNavigate={onNavigate}
                busy={
                  (accept.isPending && accept.variables === conversation.id) ||
                  (decline.isPending && decline.variables === conversation.id)
                }
                onAccept={() => accept.mutate(conversation.id)}
                onDecline={() => decline.mutate(conversation.id)}
              />
            ) : (
              <ConversationRow conversation={conversation} onNavigate={onNavigate} />
            )}
          </li>
        ))}
      </ul>
      {pages.hasNextPage ? (
        <button
          type="button"
          onClick={() => void pages.fetchNextPage()}
          disabled={pages.isFetchingNextPage}
          className="min-h-11 self-center rounded-full px-4 text-sm font-semibold disabled:opacity-50"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("loadMore")}
        </button>
      ) : null}
    </div>
  );
}

/**
 * «Message requests (N)»: the way into the requests folder from an inbox.
 * Shown only while there are requests. N counts the requests on the first
 * page, with «+» when there are more.
 */
export function MessageRequestsEntry({ href = REQUESTS_HREF, onNavigate }: { href?: string; onNavigate?: () => void }) {
  const t = useTranslations("Conversations");
  const pages = useConversationList("requests");
  const firstPage = pages.data?.pages[0];
  const count = listedConversations(firstPage ? [firstPage] : []).length;
  if (count === 0) return null;
  const label = pages.hasNextPage ? `${count}+` : String(count);
  const unread = (firstPage?.conversations ?? []).some((conversation) => conversation.unread && conversation.last_message);
  return (
    <Link
      href={href}
      onClick={onNavigate}
      className="flex min-h-12 items-center justify-between gap-3 rounded-2xl px-4 py-2 text-sm font-semibold outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)]"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      data-testid="message-requests-entry"
    >
      <span className="truncate">{t("requestsEntry", { count: label })}</span>
      <span className="flex shrink-0 items-center gap-2" aria-hidden="true">
        {unread ? <span className="h-2 w-2 rounded-full" style={{ background: "var(--primary)" }} /> : null}
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="rtl:rotate-180" style={{ color: "var(--dim)" }}>
          <path d="m9 18 6-6-6-6" />
        </svg>
      </span>
    </Link>
  );
}

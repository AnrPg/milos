"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient, type InfiniteData } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  CONVERSATIONS_UNREAD_KEY,
  CONVERSATION_LISTS_KEY,
  conversationKey,
  conversationMessagesKey,
  fetchConversation,
  fetchConversationMessages,
  markConversationRead,
  sendConversationMessage,
  type PersonMessage,
  type PersonMessagePage,
} from "@/api/conversations";
import { MessageComposer } from "@/components/chat/MessageComposer";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";

import { BuddyBadge, RequestButtons, useShortTime } from "./ConversationRow";
import { personLabel, settledPending, shownMessages, type PendingMessage } from "./conversation-model";
import { CONVERSATIONS_FALLBACK_REFETCH_MS } from "./conversations-realtime";
import { REQUESTS_HREF, useConversationsToken, useRequestActions } from "./use-conversations";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** The API's limit on one message (ADR-193 §3). */
export const MESSAGE_MAX_LENGTH = 2000;

function newOperationId() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID();
  // Old browsers without randomUUID: a v4-shaped id from getRandomValues.
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** Puts a sent message at the top of the newest page, once. */
function withSent(data: InfiniteData<PersonMessagePage, string | null> | undefined, message: PersonMessage) {
  if (!data) return data;
  if (data.pages.some((page) => (page.messages ?? []).some((item) => item.id === message.id))) return data;
  const [first, ...rest] = data.pages;
  return { ...data, pages: [{ ...first, messages: [message, ...(first?.messages ?? [])] }, ...rest] };
}

/**
 * One person conversation (ADR-193 §3): the person, the messages with the
 * newest at the bottom and older ones on demand, Accept · Decline while it
 * is a request, and the composer. Sends show at once and carry a
 * client_operation_id, so a retry never writes twice. Opening it, and each
 * new message while it is open, marks it read. No page chrome, so any inbox
 * can embed it.
 */
export function ConversationView({ conversationId, onDeclined }: { conversationId: string; onDeclined?: () => void }) {
  const t = useTranslations("Conversations");
  const tUi = useUiTranslations();
  const router = useRouter();
  const token = useConversationsToken();
  const queryClient = useQueryClient();
  const time = useShortTime();
  const [draft, setDraft] = useState("");
  const [pending, setPending] = useState<PendingMessage[]>([]);
  const bottom = useRef<HTMLDivElement | null>(null);
  const messagesKey = useMemo(() => conversationMessagesKey(conversationId), [conversationId]);

  const conversation = useQuery({
    queryKey: conversationKey(conversationId),
    enabled: Boolean(token),
    queryFn: () => fetchConversation(token!, conversationId),
    retry: (count, error) => !(error instanceof ApiError && error.status === 404) && count < 2,
  });
  const pages = useInfiniteQuery({
    queryKey: messagesKey,
    enabled: Boolean(token) && conversation.isSuccess,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchConversationMessages(token!, conversationId, pageParam),
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    refetchInterval: CONVERSATIONS_FALLBACK_REFETCH_MS,
  });

  const loaded = pages.data?.pages;
  const shown = useMemo(() => shownMessages(loaded ?? [], pending), [loaded, pending]);
  const newestKey = shown[shown.length - 1]?.key ?? null;

  // A refetch that brings back a pending send settles it.
  useEffect(() => {
    if (!loaded) return;
    queueMicrotask(() => setPending((current) => {
      const next = settledPending(current, loaded);
      return next.length === current.length ? current : next;
    }));
  }, [loaded]);

  useEffect(() => {
    if (newestKey) bottom.current?.scrollIntoView?.({ block: "end" });
  }, [newestKey]);

  const refreshLists = () => {
    void queryClient.invalidateQueries({ queryKey: CONVERSATION_LISTS_KEY });
    void queryClient.invalidateQueries({ queryKey: CONVERSATIONS_UNREAD_KEY, exact: true });
  };

  const markRead = useMutation({
    mutationFn: () => markConversationRead(token!, conversationId),
    onSuccess: (updated) => {
      queryClient.setQueryData(conversationKey(conversationId), updated);
      refreshLists();
    },
  });
  const markReadNow = markRead.mutate;
  const marking = markRead.isPending;
  const markFailed = markRead.isError;
  const unread = conversation.data?.unread ?? false;
  // On open, and whenever a new message makes it unread again (the realtime
  // event refetches the conversation). A failed mark is not retried in a loop.
  useEffect(() => {
    if (unread && token && !marking && !markFailed) markReadNow();
  }, [unread, token, marking, markFailed, markReadNow]);

  const send = useMutation({
    mutationFn: (item: PendingMessage) => sendConversationMessage(token!, conversationId, item.body, item.client_operation_id),
    onSuccess: (message, item) => {
      queryClient.setQueryData(messagesKey, (data: InfiniteData<PersonMessagePage, string | null> | undefined) => withSent(data, message));
      setPending((current) => current.filter((entry) => entry.client_operation_id !== item.client_operation_id));
      // Replying to a request accepts it, so the folder may have changed.
      void queryClient.invalidateQueries({ queryKey: conversationKey(conversationId), exact: true });
      refreshLists();
    },
    onError: (_error, item) => {
      setPending((current) =>
        current.map((entry) => (entry.client_operation_id === item.client_operation_id ? { ...entry, status: "failed" } : entry)),
      );
    },
  });

  function submit() {
    const body = draft.trim();
    if (!body || body.length > MESSAGE_MAX_LENGTH || !token) return;
    const item: PendingMessage = { client_operation_id: newOperationId(), body, created_at: new Date().toISOString(), status: "sending" };
    setPending((current) => [...current, item]);
    setDraft("");
    send.mutate(item);
  }

  function retry(item: PendingMessage) {
    const again: PendingMessage = { ...item, status: "sending" };
    setPending((current) => current.map((entry) => (entry.client_operation_id === item.client_operation_id ? again : entry)));
    send.mutate(again);
  }

  function discard(item: PendingMessage) {
    setPending((current) => current.filter((entry) => entry.client_operation_id !== item.client_operation_id));
  }

  const { accept, decline } = useRequestActions();

  if (conversation.isPending) {
    return (
      <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>
        {t("loading")}
      </p>
    );
  }
  if (conversation.isError || !conversation.data) {
    const missing = conversation.error instanceof ApiError && conversation.error.status === 404;
    return (
      <div data-testid="conversation-unavailable"><ErrorNotice>
        {missing ? t("unavailable") : localizeError(conversation.error, tUi)}
      </ErrorNotice></div>
    );
  }

  const current = conversation.data;
  const name = personLabel(current.person, t("someone"));
  const isRequest = current.folder === "requests" && !current.started_by_me;
  const tooLong = draft.trim().length > MESSAGE_MAX_LENGTH;
  const actionError = accept.error ?? decline.error;

  return (
    <div className="flex min-w-0 flex-col gap-4" data-testid="conversation-view">
      <Link
        href={`/people/${encodeURIComponent(current.person.id)}`}
        className="flex min-w-0 items-center gap-3 self-start rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)]"
        aria-label={t("viewProfile", { name })}
      >
        <PersonAvatar name={name} url={current.person.avatar_url} size={44} />
        <span className="min-w-0">
          <span className="flex min-w-0 items-center gap-2">
            <span className="truncate text-xl font-extrabold" style={{ color: "var(--text)" }}>
              {name}
            </span>
            {current.buddy ? <BuddyBadge /> : null}
          </span>
          {current.person.handle ? (
            <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
              @{current.person.handle}
            </span>
          ) : null}
        </span>
      </Link>

      {isRequest ? (
        <section
          aria-label={t("requestTitle")}
          className="flex flex-col gap-3 rounded-2xl p-4"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
          data-testid="conversation-request-banner"
        >
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("requestBanner", { name })}
          </p>
          <p className="text-xs" style={{ color: "var(--text-soft)" }}>
            {t("requestBannerHint", { name })}
          </p>
          <RequestButtons
            busy={accept.isPending || decline.isPending}
            onAccept={() => accept.mutate(conversationId)}
            onDecline={() =>
              decline.mutate(conversationId, {
                onSuccess: () => (onDeclined ? onDeclined() : router.push(REQUESTS_HREF)),
              })
            }
          />
          {actionError ? (
            <ErrorNotice>
              {localizeError(actionError, tUi)}
            </ErrorNotice>
          ) : null}
        </section>
      ) : null}

      <section
        aria-label={t("chatWith", { name })}
        className="flex min-h-64 min-w-0 flex-col gap-2 rounded-2xl p-4"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        {pages.hasNextPage ? (
          <button
            type="button"
            onClick={() => void pages.fetchNextPage()}
            disabled={pages.isFetchingNextPage}
            className="min-h-9 self-center rounded-full px-3 text-xs font-semibold disabled:opacity-50"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("earlier")}
          </button>
        ) : null}
        {pages.isPending ? (
          <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>
            {t("loading")}
          </p>
        ) : null}
        {pages.isError ? (
          <ErrorNotice>
            {localizeError(pages.error, tUi)}
          </ErrorNotice>
        ) : null}
        {!pages.isPending && shown.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>
            {t("chatEmpty", { name })}
          </p>
        ) : null}
        <ol className="flex min-w-0 flex-col gap-2" aria-live="polite">
          {shown.map((item) =>
            item.kind === "sent" ? (
              <Bubble key={item.key} mine={item.message.mine} body={item.message.body} meta={time(item.message.created_at)} />
            ) : (
              <Bubble
                key={item.key}
                mine
                body={item.pending.body}
                faded={item.pending.status === "sending"}
                meta={item.pending.status === "sending" ? t("sending") : t("failed")}
                failed={item.pending.status === "failed"}
                onRetry={() => retry(item.pending)}
                onDiscard={() => discard(item.pending)}
              />
            ),
          )}
        </ol>
        <div ref={bottom} />
      </section>

      <MessageComposer
        value={draft}
        onChange={setDraft}
        onSend={submit}
        placeholder={t("placeholder")}
        sendLabel={t("send")}
        error={tooLong ? t("tooLong", { max: MESSAGE_MAX_LENGTH }) : null}
      />
    </div>
  );
}

function Bubble({
  mine,
  body,
  meta,
  faded = false,
  failed = false,
  onRetry,
  onDiscard,
}: {
  mine: boolean;
  body: string;
  meta: string;
  faded?: boolean;
  failed?: boolean;
  onRetry?: () => void;
  onDiscard?: () => void;
}) {
  const t = useTranslations("Conversations");
  return (
    <li className={["flex min-w-0 max-w-[85%] flex-col gap-0.5", mine ? "self-end items-end" : "self-start items-start"].join(" ")}>
      <span
        className="max-w-full whitespace-pre-wrap break-words rounded-2xl px-3 py-2 text-sm"
        style={{
          background: mine ? "var(--primary)" : "var(--panel-raised)",
          color: mine ? "var(--primary-contrast)" : "var(--text)",
          opacity: faded ? 0.6 : 1,
          border: failed ? "1px solid var(--danger)" : undefined,
        }}
      >
        {body}
      </span>
      <span className="flex items-center gap-2 text-[11px]" style={{ color: failed ? "var(--danger)" : "var(--dim)" }}>
        {meta}
        {failed ? (
          <>
            <button type="button" onClick={onRetry} className="min-h-6 font-semibold underline" style={{ color: "var(--text)" }}>
              {t("retry")}
            </button>
            <button type="button" onClick={onDiscard} className="min-h-6 font-semibold underline" style={{ color: "var(--dim)" }}>
              {t("discard")}
            </button>
          </>
        ) : null}
      </span>
    </li>
  );
}

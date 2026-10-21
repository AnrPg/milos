"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { BUDDIES_KEY, fetchBuddyMessages, markBuddyMessagesRead, sendBuddyMessage, type BuddyMessage } from "@/api/buddies";
import { ErrorLine } from "@/components/community/Sheet";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { BackLink } from "./BuddyBits";
import { overviewLists, personName } from "./buddy-model";
import { buddyErrorMessage } from "./errors";
import { useBuddies, useBuddyToken } from "./use-buddies";

/**
 * The pair's own conversation (ADR-160 §6): replies to «Χρειάζομαι
 * στήριξη» land here, and either can keep talking while the link is
 * active. Older messages page in on request; what you open is marked read,
 * your own messages say when they were read; an ended link stays readable
 * but nobody can write.
 */
export function BuddyChat({ linkId }: { linkId: string }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const format = useFormatter();
  const token = useBuddyToken();
  const queryClient = useQueryClient();
  const overview = useBuddies();
  const [draft, setDraft] = useState("");
  const bottom = useRef<HTMLDivElement | null>(null);
  const messagesKey = useMemo(() => [...BUDDIES_KEY, linkId, "messages"], [linkId]);

  const pages = useInfiniteQuery({
    queryKey: messagesKey,
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchBuddyMessages(token!, linkId, pageParam),
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    refetchInterval: 10_000,
  });

  const { buddies, supporting, invitations } = overviewLists(overview.data);
  const link = [...buddies, ...supporting, ...invitations].find((item) => item.id === linkId) ?? null;
  const name = personName(link?.person, t("someone"));
  const first = pages.data?.pages[0];
  const readOnly = first?.read_only ?? (link ? link.status !== "active" : false);
  const unread = first?.unread ?? 0;

  const messages = useMemo(() => {
    const all = (pages.data?.pages ?? []).flatMap((page) => page.messages ?? []);
    const seen = new Set<string>();
    return all.filter((message) => (seen.has(message.id) ? false : (seen.add(message.id), true))).reverse();
  }, [pages.data]);
  const lastMineRead = [...messages].reverse().find((message) => message.mine && message.read_at)?.id ?? null;
  const newestId = messages[messages.length - 1]?.id ?? null;

  const markRead = useMutation({
    mutationFn: () => markBuddyMessagesRead(token!, linkId),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: BUDDIES_KEY, exact: true }),
  });
  const markReadNow = markRead.mutate;
  const marking = markRead.isPending;
  useEffect(() => {
    if (unread > 0 && token && !marking) markReadNow();
  }, [unread, token, marking, markReadNow]);

  useEffect(() => {
    if (newestId) bottom.current?.scrollIntoView?.({ block: "end" });
  }, [newestId]);

  const send = useMutation({
    mutationFn: (body: string) => sendBuddyMessage(token!, linkId, body),
    onSuccess: () => {
      setDraft("");
      void queryClient.invalidateQueries({ queryKey: messagesKey });
    },
  });

  return (
    <div className="flex flex-col gap-4">
      <div>
        <BackLink href="/me/buddy">{t("title")}</BackLink>
        <div className="flex items-center gap-3">
          <PersonAvatar name={name} url={link?.person?.avatar_url} size={40} />
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{name}</h1>
        </div>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("chatPrivate")}</p>
      </div>

      <section
        aria-label={t("chatWith", { name })}
        className="flex min-h-64 flex-col gap-2 rounded-2xl p-4"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        data-testid="buddy-chat"
      >
        {pages.hasNextPage ? (
          <button
            type="button"
            onClick={() => void pages.fetchNextPage()}
            disabled={pages.isFetchingNextPage}
            className="self-center rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("earlier")}
          </button>
        ) : null}
        {pages.isPending ? <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
        {pages.isError ? <ErrorLine message={buddyErrorMessage(pages.error, t, tUi)} /> : null}
        {!pages.isPending && messages.length === 0 ? <p className="text-sm" style={{ color: "var(--muted)" }}>{t("chatEmpty")}</p> : null}
        <ol className="flex flex-col gap-2" aria-live="polite">
          {messages.map((message) => (
            <Bubble
              key={message.id}
              message={message}
              time={format.dateTime(new Date(message.created_at), { hour: "2-digit", minute: "2-digit", day: "numeric", month: "short" })}
              readLabel={message.id === lastMineRead ? t("read") : null}
            />
          ))}
        </ol>
        <div ref={bottom} />
      </section>

      {readOnly ? (
        <p className="rounded-2xl px-4 py-3 text-sm" role="note" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }} data-testid="chat-read-only">
          {t("chatReadOnly")}
        </p>
      ) : (
        <form
          className="flex gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            const body = draft.trim();
            if (body) send.mutate(body);
          }}
        >
          <textarea
            value={draft}
            maxLength={2000}
            rows={2}
            onChange={(event) => setDraft(event.target.value)}
            placeholder={t("chatPlaceholder")}
            aria-label={t("chatPlaceholder")}
            className="min-h-11 min-w-0 flex-1 resize-none rounded-2xl px-4 py-2 text-sm"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
          <button
            type="submit"
            disabled={send.isPending || !draft.trim()}
            className="min-h-11 self-end rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--bg)" }}
          >
            {t("replySend")}
          </button>
        </form>
      )}
      <ErrorLine message={buddyErrorMessage(send.error, t, tUi)} />
    </div>
  );
}

function Bubble({ message, time, readLabel }: { message: BuddyMessage; time: string; readLabel: string | null }) {
  return (
    <li className={["flex max-w-[85%] flex-col gap-0.5", message.mine ? "self-end items-end" : "self-start items-start"].join(" ")}>
      <span
        className="whitespace-pre-wrap rounded-2xl px-3 py-2 text-sm"
        style={{
          background: message.mine ? "var(--primary)" : "var(--panel-raised)",
          color: message.mine ? "var(--bg)" : "var(--text)",
        }}
      >
        {message.body}
      </span>
      <span className="text-[11px]" style={{ color: "var(--dim)" }}>
        {time}
        {readLabel ? ` · ${readLabel}` : ""}
      </span>
    </li>
  );
}

"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useLocale, useTranslations } from "next-intl";

import {
  BLOCKS_KEY,
  PARTNERS_KEY,
  PARTNER_MATCHES_KEY,
  blockPerson,
  endPartnerMatch,
  fetchPartnerMessages,
  markPartnerMessagesRead,
  partnerMessagesKey,
  sendPartnerMessage,
  type PartnerMessage,
} from "@/api/partners";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { inboxHref } from "@/components/chat/inbox/inbox-model";
import { BackLink } from "@/components/ui/BackLink";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { useUiTranslations } from "@/i18n/ui";
import { withClock } from "@/lib/clock";
import { useRealtimeFallbackInterval } from "@/lib/realtime";

import { PartnerReportSheet } from "./PartnerReportSheet";
import { PartnerSuggestions } from "./PartnerSuggestions";
import { partnerErrorMessage } from "./errors";
import { planHref } from "./partners-model";
import { PARTNERS_FALLBACK_REFETCH_MS } from "./partners-realtime";
import { usePartnerMatches, usePartnersToken } from "./use-partners";

type Confirm = "end" | "block" | null;

/**
 * A match's own conversation (ADR-280): «Βρήκατε συναθλητή» with up to three
 * ideas to train together («Πρότεινε» posts one as a plan), «Πάμε μαζί;»
 * next to the message box, and ⋯ to end the match, block or report the
 * person to the Palee team. An ended match stays readable; nobody can write.
 */
export function PartnerChat({ matchId }: { matchId: string }) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const format = useFormatter();
  const locale = useLocale();
  const router = useRouter();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const matches = usePartnerMatches();
  const [draft, setDraft] = useState("");
  const [confirm, setConfirm] = useState<Confirm>(null);
  const [reporting, setReporting] = useState(false);
  const bottom = useRef<HTMLDivElement | null>(null);
  const input = useRef<HTMLTextAreaElement | null>(null);
  const messagesKey = useMemo(() => partnerMessagesKey(matchId), [matchId]);

  const fallback = useRealtimeFallbackInterval(PARTNERS_FALLBACK_REFETCH_MS);
  const pages = useInfiniteQuery({
    queryKey: messagesKey,
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchPartnerMessages(token!, matchId, pageParam),
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    refetchInterval: fallback,
  });

  const match = matches.data?.find((item) => item.id === matchId) ?? null;
  const name = match?.person.nickname ?? t("someone");
  const first = pages.data?.pages[0];
  const readOnly = first?.read_only ?? match?.read_only ?? false;
  const unread = first?.unread ?? 0;
  const active = match?.status === "active" && !readOnly;

  const messages = useMemo(() => {
    const all = (pages.data?.pages ?? []).flatMap((page) => page.messages ?? []);
    const seen = new Set<string>();
    return all.filter((message) => (seen.has(message.id) ? false : (seen.add(message.id), true))).reverse();
  }, [pages.data]);
  const newestId = messages[messages.length - 1]?.id ?? null;

  const markRead = useMutation({
    mutationFn: () => markPartnerMessagesRead(token!, matchId),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: PARTNER_MATCHES_KEY, exact: true }),
  });
  const markReadNow = markRead.mutate;
  const marking = markRead.isPending;
  useEffect(() => {
    if (unread > 0 && token && !marking) markReadNow();
  }, [unread, token, marking, markReadNow]);

  useEffect(() => {
    if (newestId) bottom.current?.scrollIntoView?.({ block: "end" });
  }, [newestId]);

  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: messagesKey });
    void queryClient.invalidateQueries({ queryKey: PARTNER_MATCHES_KEY, exact: true });
  };

  const send = useMutation({
    mutationFn: (body: string) => sendPartnerMessage(token!, matchId, body),
    onSuccess: () => {
      setDraft("");
      refresh();
    },
  });

  const end = useMutation({
    mutationFn: async (kind: Exclude<Confirm, null>) => {
      if (kind === "block" && match) await blockPerson(token!, match.partner_id);
      else await endPartnerMatch(token!, matchId);
      return kind;
    },
    onSuccess: (kind) => {
      setConfirm(null);
      void queryClient.invalidateQueries({ queryKey: PARTNERS_KEY });
      if (kind === "block") {
        void queryClient.invalidateQueries({ queryKey: BLOCKS_KEY });
        router.push(inboxHref({ filter: "partners" }));
      }
    },
  });

  /** «Πάμε μαζί;»: starts the message for me to finish with where and when. */
  const goTogether = () => {
    setDraft((current) => (current.trim() ? current : `${t("goTogetherDraft")} `));
    input.current?.focus();
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <BackLink href={inboxHref({ filter: "partners" })} className="inline-flex min-h-11 items-center text-sm font-semibold" style={{ color: "var(--primary)" }}>{t("messagesBack")}</BackLink>
          <div className="flex items-center gap-3">
            <PersonAvatar name={name} url={match?.person.avatar_url} size={40} />
            <div className="min-w-0">
              <h1 className="truncate text-2xl font-extrabold" style={{ color: "var(--text)" }}>{name}</h1>
              <p className="truncate text-xs" style={{ color: "var(--dim)" }}>{t("chatSubtitle")}</p>
            </div>
          </div>
        </div>
        {match ? (
          <div className="mt-11">
            <MoreMenu
              label={t("moreActions")}
              testId="partner-more"
              items={[
                ...(match.status === "active" ? [{ label: t("endMatch"), onSelect: () => setConfirm("end") }] : []),
                { label: t("block", { name }), onSelect: () => setConfirm("block"), tone: "danger" as const },
                { label: t("report", { name }), onSelect: () => setReporting(true), tone: "danger" as const },
              ]}
            />
          </div>
        ) : null}
      </div>

      {active ? <PartnerSuggestions matchId={matchId} name={name} onProposed={refresh} /> : null}

      <section
        aria-label={t("chatWith", { name })}
        className="flex min-h-64 flex-col gap-2 rounded-2xl p-4"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        data-testid="partner-chat"
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
        {pages.isPending ? <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
        {pages.isError ? <ErrorLine message={partnerErrorMessage(pages.error, t, tUi)} /> : null}
        {!pages.isPending && messages.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("chatEmpty", { name })}</p>
        ) : null}
        <ol className="flex flex-col gap-2" aria-live="polite">
          {messages.map((message) => (
            <Bubble
              key={message.id}
              message={message}
              time={format.dateTime(new Date(message.created_at), withClock(locale, { hour: "2-digit", minute: "2-digit", day: "numeric", month: "short" }))}
            />
          ))}
        </ol>
        <div ref={bottom} />
      </section>

      {readOnly ? (
        <p className="rounded-2xl px-4 py-3 text-sm" role="note" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }} data-testid="partner-read-only">
          {t("chatReadOnly")}
        </p>
      ) : (
        <form
          className="flex flex-col gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            const body = draft.trim();
            if (body) send.mutate(body);
          }}
        >
          <div className="flex gap-2">
            <textarea
              ref={input}
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
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {t("send")}
            </button>
          </div>
          <button
            type="button"
            onClick={goTogether}
            className="min-h-11 self-start rounded-full px-4 text-sm font-bold"
            style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }}
            data-testid="partner-go-together"
          >
            {t("goTogether")}
          </button>
          <ErrorLine message={partnerErrorMessage(send.error, t, tUi)} />
        </form>
      )}

      {confirm ? (
        <Sheet
          labelId={`partner-confirm-${matchId}`}
          title={confirm === "end" ? t("endTitle") : t("blockTitle", { name })}
          onClose={() => setConfirm(null)}
          footer={
            <>
              <SheetButton onClick={() => setConfirm(null)}>{t("cancel")}</SheetButton>
              <SheetButton primary disabled={end.isPending} onClick={() => end.mutate(confirm)}>
                {confirm === "end" ? t("endConfirm") : t("blockConfirm")}
              </SheetButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{confirm === "end" ? t("endBody", { name }) : t("blockBody", { name })}</p>
          <ErrorLine message={partnerErrorMessage(end.error, t, tUi)} />
        </Sheet>
      ) : null}
      {reporting && match ? (
        <PartnerReportSheet
          targetId={match.partner_id}
          name={name}
          onClose={() => setReporting(false)}
          onReported={() => {
            void queryClient.invalidateQueries({ queryKey: PARTNERS_KEY });
            void queryClient.invalidateQueries({ queryKey: BLOCKS_KEY });
            router.push(inboxHref({ filter: "partners" }));
          }}
        />
      ) : null}
    </div>
  );
}

function Bubble({ message, time }: { message: PartnerMessage; time: string }) {
  const t = useTranslations("Partners");
  const format = useFormatter();
  const locale = useLocale();
  const mine = message.mine;
  return (
    <li className={["flex max-w-[85%] flex-col gap-0.5", mine ? "items-end self-end" : "items-start self-start"].join(" ")}>
      {message.kind === "plan" && message.plan ? (
        <Link
          href={planHref(message.plan)}
          className="flex flex-col gap-0.5 rounded-2xl px-3 py-2 text-sm"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--primary)", color: "var(--text)" }}
          data-testid="partner-plan"
        >
          <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t(`planKind_${message.plan.kind}`)}</span>
          <span className="font-bold">{message.plan.title}</span>
          <span>{format.dateTime(new Date(message.plan.starts_at), withClock(locale, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }))}</span>
          {message.plan.place ? <span style={{ color: "var(--text-soft)" }}>{message.plan.place}</span> : null}
          {message.body ? <span className="whitespace-pre-wrap" style={{ color: "var(--text-soft)" }}>{message.body}</span> : null}
          <span className="text-xs font-semibold" style={{ color: "var(--primary)" }}>{t(`planOpen_${message.plan.kind}`)}</span>
        </Link>
      ) : (
        <span
          className="whitespace-pre-wrap rounded-2xl px-3 py-2 text-sm"
          style={{ background: mine ? "var(--primary)" : "var(--panel-raised)", color: mine ? "var(--primary-contrast)" : "var(--text)" }}
        >
          {message.body}
        </span>
      )}
      <span className="text-[11px]" style={{ color: "var(--dim)" }}>{time}</span>
    </li>
  );
}

"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

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
import { ReportSheet } from "@/components/community/ReportSheet";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { PartnerPlanSheet } from "./PartnerPlanSheet";
import { partnerErrorMessage } from "./errors";
import { PARTNERS_FALLBACK_REFETCH_MS } from "./partners-realtime";
import { usePartnerMatches, usePartnersToken } from "./use-partners";
import { Popover } from "@/components/ui/Popover";
import { inboxHref } from "@/components/chat/inbox/inbox-model";
import { useRealtimeFallbackInterval } from "@/lib/realtime";
import { BackLink } from "@/components/ui/BackLink";

type Confirm = "end" | "block" | null;

/**
 * A match's own conversation (ADR-169 §7, §8): messages, «Κλείστε μαζί» for
 * a class at the gym, and ⋯ to end the match, block or report the person.
 * An ended match, or one where someone left the club, stays readable but
 * nobody can write.
 */
export function PartnerChat({ matchId }: { matchId: string }) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const format = useFormatter();
  const router = useRouter();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const matches = usePartnerMatches();
  const [draft, setDraft] = useState("");
  const [menu, setMenu] = useState(false);
  const menuButtonRef = useRef<HTMLButtonElement>(null);
  const [confirm, setConfirm] = useState<Confirm>(null);
  const [reporting, setReporting] = useState(false);
  const [planning, setPlanning] = useState(false);
  const bottom = useRef<HTMLDivElement | null>(null);
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
      if (kind === "block" && match) await blockPerson(token!, match.person.id);
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

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <BackLink href={inboxHref({ filter: "partners" })} className="inline-flex min-h-11 items-center text-sm font-semibold" style={{ color: "var(--primary)" }}>{t("messagesBack")}</BackLink>
          <div className="flex items-center gap-3">
            <PersonAvatar name={name} url={match?.person.avatar_url} size={40} />
            <div className="min-w-0">
              <h1 className="truncate text-2xl font-extrabold" style={{ color: "var(--text)" }}>{name}</h1>
              <p className="truncate text-xs" style={{ color: "var(--dim)" }}>
                {match?.club_name ? t("chatSubtitle", { club: match.club_name }) : t("title")}
              </p>
            </div>
          </div>
        </div>
        {match ? (
          <div className="relative">
            <button
              ref={menuButtonRef}
              type="button"
              aria-haspopup="menu"
              aria-expanded={menu}
              aria-label={t("moreActions")}
              onClick={() => setMenu((open) => !open)}
              className="mt-11 flex h-11 w-11 items-center justify-center rounded-full text-lg"
              style={{ background: "var(--panel-raised)", color: "var(--text)" }}
            >
              ⋯
            </button>
            <Popover
              anchorRef={menuButtonRef}
              open={menu}
              onClose={() => setMenu(false)}
              align="end"
              width={224}
              className="rounded-2xl"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <ul role="menu" aria-label={t("moreActions")} className="flex flex-col">
                {match.status === "active" ? (
                  <MenuItem onClick={() => (setMenu(false), setConfirm("end"))}>{t("endMatch")}</MenuItem>
                ) : null}
                <MenuItem onClick={() => (setMenu(false), setConfirm("block"))}>{t("block", { name })}</MenuItem>
                {match.partner_profile_id ? (
                  <MenuItem danger onClick={() => (setMenu(false), setReporting(true))}>{t("report", { name })}</MenuItem>
                ) : null}
              </ul>
            </Popover>
          </div>
        ) : null}
      </div>

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
            className="self-center rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50"
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
              time={format.dateTime(new Date(message.created_at), { hour: "2-digit", minute: "2-digit", day: "numeric", month: "short" })}
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
        <>
          {match?.plannable ? (
            <button
              type="button"
              onClick={() => setPlanning(true)}
              className="min-h-11 self-start rounded-full px-4 text-sm font-bold"
              style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }}
              data-testid="partner-plan-open"
            >
              {t("planOpen")}
            </button>
          ) : null}
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
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {t("send")}
            </button>
          </form>
        </>
      )}
      <ErrorLine message={partnerErrorMessage(send.error, t, tUi)} />

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
      {reporting && match?.partner_profile_id ? (
        <ReportSheet
          target="partner"
          targetId={match.partner_profile_id}
          onClose={() => setReporting(false)}
          onReported={() => {
            void queryClient.invalidateQueries({ queryKey: PARTNERS_KEY });
            void queryClient.invalidateQueries({ queryKey: BLOCKS_KEY });
          }}
        />
      ) : null}
      {planning ? <PartnerPlanSheet matchId={matchId} name={name} onClose={() => setPlanning(false)} onPlanned={refresh} /> : null}
    </div>
  );
}

function MenuItem({ onClick, danger, children }: { onClick: () => void; danger?: boolean; children: string }) {
  return (
    <li role="none">
      <button
        type="button"
        role="menuitem"
        onClick={onClick}
        className="min-h-11 w-full px-4 text-start text-sm font-semibold"
        style={{ color: danger ? "var(--danger)" : "var(--text)" }}
      >
        {children}
      </button>
    </li>
  );
}

function Bubble({ message, time }: { message: PartnerMessage; time: string }) {
  const t = useTranslations("Partners");
  const format = useFormatter();
  const mine = message.mine;
  return (
    <li className={["flex max-w-[85%] flex-col gap-0.5", mine ? "self-end items-end" : "self-start items-start"].join(" ")}>
      {message.kind === "plan" && message.plan ? (
        <Link
          href={`/box/schedule?open_slot=${encodeURIComponent(message.plan.class_id)}`}
          className="flex flex-col gap-0.5 rounded-2xl px-3 py-2 text-sm"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--primary)", color: "var(--text)" }}
          data-testid="partner-plan"
        >
          <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("planEyebrow")}</span>
          <span className="font-bold">{message.plan.name ?? t("planClass")}</span>
          <span>{format.dateTime(new Date(message.plan.scheduled_at), { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })}</span>
          {message.body ? <span className="whitespace-pre-wrap" style={{ color: "var(--text-soft)" }}>{message.body}</span> : null}
          <span className="text-xs font-semibold" style={{ color: "var(--primary)" }}>{t("planBook")}</span>
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

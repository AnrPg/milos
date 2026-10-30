"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  BOX_CONVERSATIONS_KEY,
  boxConversationKey,
  fetchBoxConversation,
  markBoxConversationRead,
  openBoxConversation,
  sendBoxMessage,
  type BoxConversation,
} from "@/api/trials";
import { useSession } from "@/components/session-provider";

import { newOperationId } from "./trial-ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { clockFormat } from "@/lib/clock";

const POLL_MS = 5_000;
const PERIODS = ["monthly", "quarterly", "semiannual", "annual"] as const;
type Period = (typeof PERIODS)[number];

/**
 * Talking to a box you're not a member of (board 6 Q6): the same thread the
 * staff see in their chats, opened from the trial follow-up («Θέλω να
 * γραφτώ», prefilled) or the trial page. The box's join offer sits on top.
 * Polls while open; live updates are for members of the gym.
 */
export function BoxChat({ slug, draft }: { slug: string; draft: string | null }) {
  const t = useTranslations("Trials");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? "";
  const [body, setBody] = useState(() => (draft === "join" ? t("joinDraft") : ""));
  const endRef = useRef<HTMLDivElement>(null);
  const lastRead = useRef<string | null>(null);

  const conversation = useQuery({
    queryKey: boxConversationKey(slug),
    enabled: Boolean(token),
    refetchInterval: POLL_MS,
    queryFn: async () => {
      try {
        return await fetchBoxConversation(token, slug);
      } catch (error) {
        // First visit: there's no thread yet.
        if (error instanceof ApiError && error.status === 404) return openBoxConversation(token, slug);
        throw error;
      }
    },
  });

  const messages = conversation.data?.messages ?? [];
  const last = messages[messages.length - 1];

  useEffect(() => {
    endRef.current?.scrollIntoView({ block: "end" });
    if (!last || last.id === lastRead.current || last.sender_id === currentUser?.id) return;
    lastRead.current = last.id;
    void markBoxConversationRead(token, slug, last.id)
      .then(() => queryClient.invalidateQueries({ queryKey: BOX_CONVERSATIONS_KEY }))
      .catch(() => undefined);
  }, [last, currentUser?.id, token, slug, queryClient]);

  const send = useMutation({
    mutationFn: (text: string) => sendBoxMessage(token, slug, text, newOperationId()),
    onSuccess: (message) => {
      setBody("");
      queryClient.setQueryData<BoxConversation>(boxConversationKey(slug), (current) =>
        current ? { ...current, messages: [...(current.messages ?? []), message] } : current,
      );
      void queryClient.invalidateQueries({ queryKey: BOX_CONVERSATIONS_KEY });
    },
  });

  if (conversation.isPending) return <p className="py-10 text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (conversation.isError || !conversation.data)
    return <p className="px-4 py-10 text-center text-sm" style={{ color: "var(--text-soft)" }}>{t("chatUnavailable")}</p>;

  const data = conversation.data;
  const staff = new Map(data.staff.map((person) => [person.id, person.nickname ?? data.box.name]));
  const pkg = data.conversion_package;
  const clock = (iso: string) =>
    clockFormat(locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
  const price = pkg
    ? new Intl.NumberFormat(locale, { style: "currency", currency: pkg.currency }).format(pkg.base_price_cents / 100)
    : null;
  const text = body.trim();

  return (
    <main className="mx-auto flex h-[calc(100dvh-4rem)] w-full max-w-xl flex-col">
      <header className="flex items-center gap-3 px-4 py-3" style={{ borderBottom: "1px solid var(--border)" }}>
        <Link href={`/b/${data.box.slug}`} className="flex min-w-0 flex-col">
          <span className="truncate text-lg font-extrabold" style={{ color: "var(--text)" }}>{data.box.name}</span>
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("chatSubtitle")}</span>
        </Link>
      </header>

      {pkg && !data.member ? (
        <section className="mx-4 mt-3 flex flex-col gap-1 rounded-2xl px-4 py-3" style={{ background: "color-mix(in srgb, var(--primary) 8%, var(--panel))", border: "1px solid color-mix(in srgb, var(--primary) 40%, transparent)" }}>
          <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("offerTitle")}</p>
          <p className="text-sm font-bold" style={{ color: "var(--text)" }}>
            {pkg.name} · {price}
            {PERIODS.includes(pkg.billing_period as Period) ? ` / ${t(`period_${pkg.billing_period as Period}`)}` : ""}
          </p>
          {pkg.description ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{pkg.description}</p> : null}
        </section>
      ) : null}

      <ol className="flex flex-1 flex-col gap-2 overflow-y-auto px-4 py-4" aria-live="polite">
        {messages.length === 0 ? (
          <li className="py-6 text-center text-sm" style={{ color: "var(--dim)" }}>{t("chatEmpty")}</li>
        ) : null}
        {messages.map((message) => {
          const mine = message.sender_id === currentUser?.id;
          return (
            <li key={message.id} className={`flex max-w-[85%] flex-col gap-0.5 ${mine ? "self-end items-end" : "self-start items-start"}`}>
              {!mine ? <span className="px-1 text-[11px] font-semibold" style={{ color: "var(--dim)" }}>{staff.get(message.sender_id) ?? data.box.name}</span> : null}
              <p
                className="whitespace-pre-line rounded-2xl px-3.5 py-2 text-sm"
                style={mine ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { background: "var(--panel-raised)", color: "var(--text)" }}
              >
                {message.body}
              </p>
              <span className="px-1 text-[10px]" style={{ color: "var(--dim)" }}>{clock(message.inserted_at)}</span>
            </li>
          );
        })}
        <div ref={endRef} />
      </ol>

      <form
        className="flex items-end gap-2 px-4 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-2"
        style={{ borderTop: "1px solid var(--border)" }}
        onSubmit={(event) => {
          event.preventDefault();
          if (text && !send.isPending) send.mutate(text);
        }}
      >
        <label className="sr-only" htmlFor="box-chat-input">{t("chatPlaceholder")}</label>
        <textarea
          id="box-chat-input"
          value={body}
          rows={Math.min(5, Math.max(1, body.split("\n").length))}
          maxLength={4000}
          onChange={(event) => setBody(event.target.value)}
          placeholder={t("chatPlaceholder")}
          className="min-h-11 flex-1 resize-none rounded-2xl px-3.5 py-2.5 text-sm"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <button
          type="submit"
          disabled={!text || send.isPending}
          className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("send")}
        </button>
      </form>
      {send.isError ? <ErrorNotice className="mx-4 mb-2">{t("sendFailed")}</ErrorNotice> : null}
    </main>
  );
}

"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { BUDDIES_KEY, QUICK_REPLIES, SUPPORT_REQUESTS_KEY, replyToSupportRequest, type SupportReplyKind, type SupportRequest } from "@/api/buddies";
import { ErrorLine } from "@/components/community/Sheet";
import { useUiTranslations } from "@/i18n/ui";

import { personName, receivedToShow, replyKey, replyText, telHref } from "./buddy-model";
import { buddyErrorMessage } from "./errors";
import { useBuddyToken, useSupportRequests } from "./use-buddies";

/**
 * The buddy's card for a request (board 15 q4 A): «Η Μαρία περνάει μια
 * δύσκολη στιγμή», her line if she wrote one, and Είμαι εδώ · Πάμε βόλτα; ·
 * Πάρε με τηλέφωνο or your own words. A reply posts into the pair's
 * conversation, which opens next; «Πάρε με τηλέφωνο» shows her phone, as
 * text to copy and a call link, only if she shares it.
 */
export function SupportRequestCard({ request, openChatAfterReply = true }: { request: SupportRequest; openChatAfterReply?: boolean }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const format = useFormatter();
  const router = useRouter();
  const token = useBuddyToken();
  const queryClient = useQueryClient();
  const [words, setWords] = useState("");
  const [phone, setPhone] = useState<{ value: string | null; linkId: string | null } | null>(null);
  const name = personName(request.sender, t("someone"));
  const quick = (request.quick_replies?.length ? request.quick_replies : QUICK_REPLIES).filter((kind) => kind !== ("text" as SupportReplyKind));
  const mine = request.replies ?? [];

  const reply = useMutation({
    mutationFn: (body: { kind: SupportReplyKind; text?: string | null }) => replyToSupportRequest(token!, request.id, body),
    onSuccess: (data, body) => {
      setWords("");
      void queryClient.invalidateQueries({ queryKey: SUPPORT_REQUESTS_KEY });
      void queryClient.invalidateQueries({ queryKey: BUDDIES_KEY });
      const linkId = data.reply?.conversation?.link_id ?? null;
      if (body.kind === "call") {
        setPhone({ value: data.sender_phone ?? null, linkId });
        return;
      }
      if (openChatAfterReply && linkId) router.push(`/me/buddy/${encodeURIComponent(linkId)}/chat`);
    },
  });

  const when = format.relativeTime(new Date(request.created_at), new Date());

  return (
    <article
      className="flex flex-col gap-3 rounded-2xl p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", borderInlineStart: "3px solid var(--primary)" }}
      aria-label={t("requestTitle", { name })}
      data-testid="support-request-card"
    >
      <div>
        <p className="text-base font-bold" style={{ color: "var(--text)" }}>{t("requestTitle", { name })}</p>
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {request.delivered_silently ? t("requestWhenQuiet", { when }) : t("requestWhen", { when })}
        </p>
      </div>
      {request.message ? <p className="text-sm" style={{ color: "var(--text)" }}>«{request.message}»</p> : null}

      {mine.length > 0 ? (
        <ul className="flex flex-col gap-1">
          {mine.map((item) => (
            <li key={item.id} className="text-sm" style={{ color: "var(--text-soft)" }}>
              {t("youReplied", { text: replyText(item, t) })}
            </li>
          ))}
        </ul>
      ) : null}

      <div className="flex flex-wrap gap-2" role="group" aria-label={t("quickReplies")}>
        {quick.map((kind) => (
          <button
            key={kind}
            type="button"
            disabled={reply.isPending}
            onClick={() => reply.mutate({ kind, text: words.trim() || null })}
            className="min-h-10 rounded-full px-3 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
          >
            {t(replyKey(kind))}
          </button>
        ))}
      </div>
      <form
        className="flex gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          if (words.trim()) reply.mutate({ kind: "text", text: words.trim() });
        }}
      >
        <input
          value={words}
          maxLength={500}
          onChange={(event) => setWords(event.target.value)}
          placeholder={t("ownWords")}
          aria-label={t("ownWords")}
          className="min-h-11 min-w-0 flex-1 rounded-2xl px-4 text-sm"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <button
          type="submit"
          disabled={reply.isPending || !words.trim()}
          className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("replySend")}
        </button>
      </form>
      <ErrorLine message={buddyErrorMessage(reply.error, t, tUi)} />

      {phone ? (
        <div className="flex flex-col gap-2 rounded-2xl p-3" role="status" style={{ background: "var(--panel-raised)" }} data-testid="sender-phone">
          {phone.value ? (
            <>
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("phoneShared", { name })}</p>
              <p className="select-all text-lg font-bold tabular-nums" style={{ color: "var(--text)" }}>{phone.value}</p>
              <a href={telHref(phone.value)} className="inline-flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                {t("callName", { name })}
              </a>
            </>
          ) : (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("phoneNotShared", { name })}</p>
          )}
          {phone.linkId ? (
            <Link href={`/me/buddy/${encodeURIComponent(phone.linkId)}/chat`} className="text-sm font-bold" style={{ color: "var(--primary)" }}>
              {t("openChat")}
            </Link>
          ) : null}
        </div>
      ) : null}
    </article>
  );
}

/** Αρχική: requests my people sent in the last day, newest first; nothing when there are none. */
export function SupportInbox() {
  const received = useSupportRequests("received");
  const [now] = useState(() => Date.now());
  const list = receivedToShow(received.data ?? [], now);
  if (list.length === 0) return null;
  return (
    <div className="flex flex-col gap-3" data-testid="support-inbox">
      {list.slice(0, 3).map((request) => (
        <SupportRequestCard key={request.id} request={request} />
      ))}
    </div>
  );
}

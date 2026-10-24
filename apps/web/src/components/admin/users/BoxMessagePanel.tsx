"use client";

import { useMutation } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { getOrCreateContextThread, MESSAGE_TOPICS, sendMessage, type MessageTopic } from "@/api/messaging";
import { TOPIC_KEYS } from "@/components/chat/message-topics";
import { useSession } from "@/components/session-provider";
import {
  inputClass,
  inputStyle,
  primaryButtonClass,
  primaryButtonStyle,
  StatusText,
} from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * «Μήνυμα από το box» (ADR-140 §6): operational staff write to the member in
 * the gym's thread with them, which any permitted staff member can continue.
 */
export function BoxMessagePanel({ userId }: { userId: string }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [body, setBody] = useState("");
  const [topic, setTopic] = useState<MessageTopic | null>(null);

  const send = useMutation({
    mutationFn: async () => {
      const { thread } = await getOrCreateContextThread(token!, "box", userId);
      await sendMessage(token!, thread.id, body.trim(), { messageType: "box_message", topic });
      return thread.id;
    },
    onSuccess: () => {
      setBody("");
      setTopic(null);
    },
  });

  return (
    <form
      className="space-y-3"
      onSubmit={(event) => {
        event.preventDefault();
        send.mutate();
      }}
    >
      <div role="radiogroup" aria-label={i18n("msgTopic")} className="flex flex-wrap gap-1.5">
        {MESSAGE_TOPICS.map((item) => (
          <button
            key={item}
            type="button"
            role="radio"
            aria-checked={topic === item}
            onClick={() => setTopic((current) => (current === item ? null : item))}
            className="rounded-full px-3 py-1 text-xs font-semibold"
            style={
              topic === item
                ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                : { background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }
            }
          >
            {i18n(TOPIC_KEYS[item])}
          </button>
        ))}
      </div>
      <textarea
        aria-label={i18n("bmBody")}
        placeholder={i18n("bmPlaceholder")}
        className={`${inputClass} min-h-24`}
        style={inputStyle}
        maxLength={5000}
        value={body}
        onChange={(event) => {
          setBody(event.target.value);
          if (send.isSuccess || send.isError) send.reset();
        }}
      />
      <div className="flex flex-wrap items-center gap-3">
        <button type="submit" disabled={!token || send.isPending || !body.trim()} className={primaryButtonClass} style={primaryButtonStyle}>
          {send.isPending ? i18n("sendingcf76551") : i18n("send9bc2575")}
        </button>
        {send.isSuccess ? (
          <Link href={`/messages?thread=${encodeURIComponent(send.data)}`} className="text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
            {i18n("bmSentOpen")}
          </Link>
        ) : null}
      </div>
      {send.isError ? <StatusText tone="error">{localizeError(send.error, i18n)}</StatusText> : null}
    </form>
  );
}

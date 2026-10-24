"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { ConversationView } from "./ConversationView";

/** /messages/:id: the page around one conversation, with the way back to the list. */
export function ConversationScreen({ conversationId }: { conversationId: string }) {
  const t = useTranslations("Conversations");
  return (
    <main className="min-h-screen px-4 py-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex w-full max-w-2xl flex-col gap-3">
        <Link
          href="/messages"
          className="inline-flex min-h-11 items-center gap-1 self-start text-sm font-semibold"
          style={{ color: "var(--primary)" }}
        >
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
            className="rtl:rotate-180"
          >
            <path d="m15 18-6-6 6-6" />
          </svg>
          {t("back")}
        </Link>
        <ConversationView key={conversationId} conversationId={conversationId} />
      </div>
    </main>
  );
}

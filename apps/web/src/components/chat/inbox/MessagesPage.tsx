"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";

import { ConversationList } from "@/components/conversations/ConversationList";

import { INBOX_PATH, inboxHref, parseInboxSegment, type InboxSegment } from "./inbox-model";
import { InboxView } from "./InboxView";

/**
 * `/messages` (vision §6.1–6.3, mockup «inbox»): Feed ✈ and `Box › Coach`
 * open it; `?filter=coach|clubs|partners` picks the segment, `?thread=<id>`
 * opens a gym thread and `?folder=requests` lists message requests
 * (ADR-193), so notifications and old links land where they point (ADR-196).
 */
export function MessagesPage() {
  const t = useTranslations("Inbox");
  const tConversations = useTranslations("Conversations");
  const router = useRouter();
  const params = useSearchParams();
  const segment = parseInboxSegment(params.get("filter"));
  const threadId = params.get("thread");
  const requests = params.get("folder") === "requests";

  const go = (next: { filter: InboxSegment; thread: string | null }) => router.replace(inboxHref(next), { scroll: false });

  return (
    <main className="mx-auto flex w-full max-w-xl flex-1 flex-col px-4 pb-6 pt-4">
      {requests ? (
        <div className="flex flex-col gap-3">
          <Link href={INBOX_PATH} className="inline-flex min-h-11 items-center gap-1 self-start text-sm font-semibold" style={{ color: "var(--primary)" }}>
            <span aria-hidden="true" className="rtl:rotate-180">←</span>
            {t("title")}
          </Link>
          <h1 className="text-2xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>
            {tConversations("requests")}
          </h1>
          <ConversationList folder="requests" />
        </div>
      ) : (
        <section
          className="flex min-h-[70vh] flex-col overflow-hidden rounded-3xl"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <InboxView
            segment={segment}
            onSegmentChange={(filter) => go({ filter, thread: null })}
            threadId={threadId}
            onThreadChange={(thread) => go({ filter: segment, thread })}
            heading={
              <h1 className="text-2xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>
                {t("title")}
              </h1>
            }
          />
        </section>
      )}
    </main>
  );
}

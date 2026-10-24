"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";

import { inboxHref, parseInboxSegment, type InboxSegment } from "./inbox-model";
import { InboxView } from "./InboxView";

/**
 * `/messages` (vision §6.1–6.3, mockup «inbox»): Feed ✈ and `Box › Coach`
 * open it; `?filter=coach|clubs|partners` picks the segment and
 * `?thread=<id>` opens a gym thread, so notifications and old links land on
 * the conversation (ADR-196).
 */
export function MessagesPage() {
  const t = useTranslations("Inbox");
  const router = useRouter();
  const params = useSearchParams();
  const segment = parseInboxSegment(params.get("filter"));
  const threadId = params.get("thread");

  const go = (next: { filter: InboxSegment; thread: string | null }) => router.replace(inboxHref(next), { scroll: false });

  return (
    <main className="mx-auto flex w-full max-w-xl flex-1 flex-col px-4 pb-6 pt-4">
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
    </main>
  );
}

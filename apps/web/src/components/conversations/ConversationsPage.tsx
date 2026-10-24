"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";

import type { ConversationFolder } from "@/api/conversations";
import { SegmentPicker } from "@/components/filters/SegmentPicker";

import { ConversationList } from "./ConversationList";
import { PeopleSearchPicker } from "./PeopleSearchPicker";
import { useConversationUnread } from "./use-conversations";

const PANEL_ID = "conversations-panel";

/**
 * /me/messages (ADR-193 §3): your person conversations, Inbox | Requests
 * (`?folder=requests`), with people search to start a new one.
 */
export function ConversationsPage() {
  const t = useTranslations("Conversations");
  const router = useRouter();
  const params = useSearchParams();
  const folder: ConversationFolder = params.get("folder") === "requests" ? "requests" : "inbox";
  const unread = useConversationUnread();

  return (
    <main className="min-h-screen px-4 py-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex w-full max-w-2xl flex-col gap-4">
        <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>
          {t("title")}
        </h1>
        <PeopleSearchPicker>
          <SegmentPicker<ConversationFolder>
            ariaLabel={t("foldersLabel")}
            idPrefix="conversations"
            panelId={PANEL_ID}
            variant="track"
            stretch
            value={folder}
            onChange={(next) => router.replace(next === "requests" ? "/me/messages?folder=requests" : "/me/messages", { scroll: false })}
            options={[
              { value: "inbox", label: t("inbox"), count: unread.inbox > 0 ? unread.inbox : null },
              { value: "requests", label: t("requests"), count: unread.requests > 0 ? unread.requests : null },
            ]}
          />
          <div id={PANEL_ID} role="tabpanel" aria-labelledby={`conversations-tab-${folder}`}>
            <ConversationList key={folder} folder={folder} />
          </div>
        </PeopleSearchPicker>
      </div>
    </main>
  );
}

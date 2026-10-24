"use client";

import type { ComponentType } from "react";

import { BuddyThreads } from "@/components/buddy/BuddyThreads";
import { PartnerThreads } from "@/components/partners/PartnerThreads";
import { useSession } from "@/components/session-provider";
import { BoxConversationsList } from "@/components/trials/BoxConversationsList";

import type { InboxSegment } from "./inbox-model";

export type InboxSectionProps = {
  /** Called when a row leaves the inbox for its own screen (closes the drawer). */
  onNavigate?: () => void;
};

/**
 * A kind of conversation the inbox lists beside the gym's threads (ADR-196).
 * Each source renders its own rows and nothing when it has none; `segments`
 * says where it files besides «Όλα» (an empty list: «Όλα» only). A new kind,
 * such as person-to-person conversations and their requests (ADR-193), joins
 * the inbox by adding an entry here; the list chrome stays the same.
 */
export type InboxSource = {
  id: string;
  segments: readonly InboxSegment[];
  Section: ComponentType<InboxSectionProps>;
};

/** Conversations with boxes you are not a member of yet (board 6 Q6). */
function BoxConversations({ onNavigate }: InboxSectionProps) {
  const { tokens } = useSession();
  return <BoxConversationsList token={tokens?.access_token ?? null} onNavigate={onNavigate} />;
}

export const INBOX_SOURCES: readonly InboxSource[] = [
  { id: "box-conversations", segments: ["clubs"], Section: BoxConversations },
  { id: "partners", segments: ["partners"], Section: PartnerThreads },
  { id: "buddies", segments: ["partners"], Section: BuddyThreads },
];

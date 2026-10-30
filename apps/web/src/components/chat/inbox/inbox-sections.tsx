"use client";

import type { ComponentType } from "react";

import { BuddyThreads } from "@/components/buddy/BuddyThreads";
import { ConversationList, MessageRequestsEntry } from "@/components/conversations/ConversationList";
import { PartnerThreads } from "@/components/partners/PartnerThreads";
import { usePartnerMatches } from "@/components/partners/use-partners";
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
 * says where it files besides «Όλα» (an empty list: «Όλα» only), and
 * `placement` whether it sits above or below the gym's threads. A new kind
 * of conversation joins the inbox by adding an entry here; the list chrome
 * stays the same.
 */
export type InboxSource = {
  id: string;
  segments: readonly InboxSegment[];
  placement: "top" | "bottom";
  Section: ComponentType<InboxSectionProps>;
};

/** Your conversations with boxes, members and newcomers alike (board 6 Q6, ADR-282). */
function BoxConversations({ onNavigate }: InboxSectionProps) {
  const { tokens } = useSession();
  return <BoxConversationsList token={tokens?.access_token ?? null} onNavigate={onNavigate} />;
}

/** «Αιτήματα μηνυμάτων (N)» (ADR-193 §3): opens `/messages?folder=requests`. */
function MessageRequests({ onNavigate }: InboxSectionProps) {
  return <MessageRequestsEntry onNavigate={onNavigate} />;
}

/** Person-to-person conversations (ADR-193 §3), latest first. */
function PersonConversations({ onNavigate }: InboxSectionProps) {
  return <ConversationList folder="inbox" hideWhenEmpty onNavigate={onNavigate} />;
}

/**
 * Whether «Συναθλητές» has anything: a training-partner match (ADR-169). Check-in
 * buddy chats are with one person, so they file under «Άτομα» (ontology §5.1).
 */
export function useHasPartners() {
  const matches = usePartnerMatches();
  return (matches.data?.length ?? 0) > 0;
}

export const INBOX_SOURCES: readonly InboxSource[] = [
  { id: "message-requests", segments: ["people"], placement: "top", Section: MessageRequests },
  { id: "person-conversations", segments: ["people"], placement: "top", Section: PersonConversations },
  { id: "box-conversations", segments: ["clubs"], placement: "bottom", Section: BoxConversations },
  { id: "partners", segments: ["partners"], placement: "bottom", Section: PartnerThreads },
  { id: "buddies", segments: ["people"], placement: "bottom", Section: BuddyThreads },
];

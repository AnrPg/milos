"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useQuery } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

import {
  createDirectThread,
  fetchThreads,
  MESSAGE_TOPICS,
  searchUsers,
  type ChatThread,
  type MessageTopic,
} from "@/api/messaging";
import { fetchCoachingRelationships } from "@/api/roles";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";
import { useChat } from "@/hooks/useChat";
import { useUiPrefs } from "@/stores/ui-prefs";
import { MessageBubble } from "./MessageBubble";
import { MessageComposer } from "./MessageComposer";
import { TOPIC_KEYS } from "./message-topics";
import { TypingIndicator } from "./TypingIndicator";
import { SemanticLabel } from "@/components/semantic-label";
import { PartnerThreads } from "@/components/partners/PartnerThreads";
import { BoxConversationsList } from "@/components/trials/BoxConversationsList";

interface SearchResult {
  id: string;
  nickname: string;
  role: string;
}

type PanelView = "list" | "thread";

export function DirectMessagesPanel({ onClose }: { onClose: () => void }) {
  const i18n = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const currentUserId = currentUser?.id ?? null;

  const { hideThread, isThreadHidden } = useUiPrefs();

  const [view, setView] = useState<PanelView>("list");
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [activeThread, setActiveThread] = useState<ChatThread | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [input, setInput] = useState("");
  const [sendError, setSendError] = useState<string | null>(null);
  const [isSending, setIsSending] = useState(false);
  const [asCoaching, setAsCoaching] = useState(false);
  const [topic, setTopic] = useState<MessageTopic | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const { membership } = useSelectedMembershipRole();
  const coaches = can(membership, "manage_coaching");

  // ADR-140 §6: a coaching message goes only to the coach's own clients.
  const clients = useQuery({
    queryKey: ["staff", "coaching-relationships", { coach: currentUserId }],
    enabled: Boolean(accessToken && currentUserId && coaches),
    queryFn: () => fetchCoachingRelationships(accessToken!, { coachUserId: currentUserId! }),
  });
  const clientIds = new Set((clients.data ?? []).map((item) => item.client_user_id));

  useEffect(() => {
    if (!accessToken) return;
    // Direct chats and the gym's threads with the member (messages from the box).
    void Promise.all([fetchThreads(accessToken, "direct"), fetchThreads(accessToken, "box")])
      .then((pages) => setThreads(pages.flatMap((d) => (Array.isArray(d.threads) ? d.threads : []))))
      .catch(() => setThreads([]));
  }, [accessToken]);

  useEffect(() => {
    if (!accessToken || searchQuery.length < 2) {
      queueMicrotask(() => setSearchResults([]));
      return;
    }

    const timeout = setTimeout(() => {
      void searchUsers(accessToken, searchQuery)
        .then((data) => {
          const filtered = data.users.filter((u) => u.id !== currentUserId);
          const existingIds = new Set(
            threads.flatMap((t) =>
              t.participants
                .filter((p) => p.user_id !== currentUserId)
                .map((p) => p.user_id),
            ),
          );
          const withThread = filtered.filter((u) => existingIds.has(u.id));
          const withoutThread = filtered.filter((u) => !existingIds.has(u.id));
          setSearchResults([...withThread, ...withoutThread].slice(0, 8));
        })
        .catch(() => setSearchResults([]));
    }, 300);
    return () => clearTimeout(timeout);
  }, [searchQuery, accessToken, currentUserId, threads]);

  const {
    messages,
    typingUsers,
    sendMessage,
    retryMessage,
    discardMessage,
    sendTypingStart,
    sendTypingStop,
  } = useChat({
    threadId: view === "thread" ? (activeThread?.id ?? null) : null,
    accessToken,
    currentUserId,
  });

  useEffect(() => {
    if (view === "thread") {
      messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, view]);

  const openThread = (thread: ChatThread) => {
    setActiveThread(thread);
    setAsCoaching(false);
    setTopic(null);
    setView("thread");
    setSearchQuery("");
    setSearchResults([]);
  };

  const startNewThread = async (targetUser: SearchResult) => {
    if (!accessToken) return;
    const { thread } = await createDirectThread(accessToken, targetUser.id);
    setThreads((prev) => (prev.some((t) => t.id === thread.id) ? prev : [thread, ...prev]));
    openThread(thread);
  };

  const handleSend = async () => {
    const draft = input;
    if (!draft.trim() || isSending) return;

    setIsSending(true);
    setSendError(null);

    try {
      await sendMessage(draft, fromBox ? "box_message" : canCoach && asCoaching ? "coaching_message" : "chat", fromBox ? topic : null);
      setInput((current) => (current === draft ? "" : current));
      sendTypingStop();
    } catch (error) {
      setSendError(error instanceof Error ? localizeError(error, i18n) : i18n("messageCouldNotBeSent7aa3b0a"));
    } finally {
      setIsSending(false);
    }
  };

  const otherParticipant = (thread: ChatThread) =>
    thread.context_type === "box"
      ? thread.participants.find((p) => p.user_id === thread.context_id)
      : thread.participants.find((p) => p.user_id !== currentUserId);

  // The member's own box thread is "Το box"; staff see the member.
  const threadName = (thread: ChatThread) =>
    thread.context_type === "box" && thread.context_id === currentUserId
      ? i18n("chatsBoxThread")
      : (otherParticipant(thread)?.nickname ?? i18n("directMessagefc7f864"));

  const fromBox = activeThread?.context_type === "box" && activeThread.context_id !== currentUserId;
  const activeOther = activeThread ? otherParticipant(activeThread) : undefined;
  const canCoach =
    activeThread?.context_type === "direct" && Boolean(activeOther && clientIds.has(activeOther.user_id));

  const visibleThreads = threads.filter((t) => !isThreadHidden(currentUserId ?? "", t.id));

  // Portalled to the body: inside the header's stacking context the member
  // tab bar would cover the composer.
  return createPortal(
    <div
      className="fixed inset-0 z-[70]"
      style={{ background: "var(--scrim)" }}
      onClick={onClose}
      role="presentation"
    >
      <aside
        aria-label={i18n("chat2ced57f")}
        className="absolute end-0 top-0 flex h-full w-full max-w-md flex-col overflow-hidden shadow-[var(--shadow-lg)] rtl:shadow-[var(--shadow-lg)]"
        style={{
          background: "var(--panel-muted)",
          borderInlineStart: "1px solid var(--border-strong)",
        }}
        onClick={(event) => event.stopPropagation()}
      >
      {/* Header */}
      <div
        className="flex items-center justify-between px-4 py-3 border-b"
        style={{ borderColor: "var(--border)" }}
      >
        {view === "thread" ? (
          <button
            type="button"
            onClick={() => setView("list")}
            className="text-sm font-medium flex items-center gap-1"
            style={{ color: "var(--text-soft)" }}
          >
            {i18n("chat67305ee")}
          </button>
        ) : (
          <span className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {i18n("chat2ced57f")}
          </span>
        )}
        <button
          type="button"
          onClick={onClose}
          className="text-lg leading-none"
          style={{ color: "var(--dim)" }}
        >
          ✕
        </button>
      </div>

      {view === "list" && (
        <>
          <div className="px-3 py-2 border-b" style={{ borderColor: "var(--border)" }}>
            <input
              type="text"
              placeholder={i18n("searchOrStartAConversationabb1d82")}
              className="w-full rounded-[1rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--card)", color: "var(--text)", border: "1px solid var(--border-strong)" }}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          <div className="scroll-area flex-1 overflow-y-auto">
            {searchResults.length === 0 ? <BoxConversationsList token={accessToken} /> : null}
            {searchResults.length === 0 ? (
              <div className="px-3 py-2">
                <PartnerThreads onNavigate={onClose} />
              </div>
            ) : null}
            {searchResults.length > 0 ? (
              searchResults.map((u) => (
                <button
                  key={u.id}
                  type="button"
                  onClick={() => void startNewThread(u)}
                  className="flex items-center gap-3 w-full px-4 py-3 text-start transition-colors"
                  style={{ background: "transparent" }}
                >
                  <div
                    className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                    style={{
                      background: "color-mix(in srgb, var(--primary) 18%, transparent)",
                      color: "var(--primary-strong)",
                    }}
                  >
                    {u.nickname[0]?.toUpperCase()}
                  </div>
                  <div>
                    <p className="text-sm font-medium" style={{ color: "var(--text)" }}>
                      {u.nickname}
                    </p>
                    <p className="text-xs" style={{ color: "var(--dim)" }}>
                      <SemanticLabel value={u.role} />
                    </p>
                  </div>
                </button>
              ))
            ) : visibleThreads.length === 0 ? (
              <p className="text-sm text-center p-4" style={{ color: "var(--dim)" }}>
                {i18n("noConversationsYetSearchToStartOne1a91cf7")}
              </p>
            ) : (
              visibleThreads.map((thread) => {
                return (
                  <div
                    key={thread.id}
                    className="relative flex items-center border-b group"
                    style={{ borderColor: "var(--border)" }}
                  >
                    <button
                      type="button"
                      onClick={() => openThread(thread)}
                      className="flex items-center gap-3 flex-1 px-4 py-3 text-start transition-colors min-w-0 pe-10"
                    >
                      <div
                        className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                        style={{
                          background: "color-mix(in srgb, var(--primary) 12%, var(--card))",
                          color: "var(--primary-strong)",
                        }}
                      >
                        {threadName(thread)[0]?.toUpperCase() ?? "?"}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium truncate" style={{ color: "var(--text)" }}>
                          {threadName(thread)}
                        </p>
                        {thread.context_type === "box" ? (
                          <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("msgKindBox")}</p>
                        ) : null}
                      </div>
                    </button>
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); hideThread(currentUserId ?? "", thread.id); }}
                      className="absolute end-3 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-60 hover:!opacity-100 rounded-lg p-1 transition-opacity text-sm leading-none"
                      style={{ color: "var(--dim)" }}
                      title={i18n("hideConversationdfb77ca")}
                    >
                      🗑️
                    </button>
                  </div>
                );
              })
            )}
          </div>
        </>
      )}

      {view === "thread" && activeThread && (
        <>
          <div className="scroll-area flex-1 overflow-y-auto flex flex-col gap-2 p-4">
            {messages.map((msg) => (
              <MessageBubble
                key={msg.id}
                message={msg}
                isOwnMessage={msg.sender_id === currentUserId}
                onRetry={retryMessage}
                onDiscard={discardMessage}
              />
            ))}
            <TypingIndicator typingUsers={typingUsers} />
            <div ref={messagesEndRef} />
          </div>

          <div
            className="p-3 border-t"
            style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}
          >
            {canCoach ? (
              <label className="mb-2 flex items-start gap-2 text-xs" style={{ color: "var(--text-soft)" }}>
                <input
                  type="checkbox"
                  className="mt-0.5"
                  checked={asCoaching}
                  onChange={(event) => setAsCoaching(event.target.checked)}
                />
                <span>
                  <span className="font-semibold">{i18n("msgSendAsCoaching")}</span>
                  <span className="block" style={{ color: "var(--dim)" }}>{i18n("msgSendAsCoachingHint")}</span>
                </span>
              </label>
            ) : null}
            {fromBox ? (
              <div role="radiogroup" aria-label={i18n("msgTopic")} className="mb-2 flex flex-wrap gap-1.5">
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
                        : { background: "var(--card)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }
                    }
                  >
                    {i18n(TOPIC_KEYS[item])}
                  </button>
                ))}
              </div>
            ) : null}
            <MessageComposer
                error={sendError ? `${sendError} ${i18n("yourDraftIsStillHereReconnectAndRetry617338d")}` : null}
                placeholder={i18n("writeAMessage24bf2a3")}
                value={input}
                onChange={(value) => {
                  setInput(value);
                  setSendError(null);
                }}
                onFocus={sendTypingStart}
                onBlur={sendTypingStop}
                onSend={() => void handleSend()}
                sendLabel={i18n("send9bc2575")}
                sending={isSending}
                sendingLabel={i18n("sendingcf76551")}
              />
          </div>
        </>
      )}
      </aside>
    </div>,
    document.body,
  );
}

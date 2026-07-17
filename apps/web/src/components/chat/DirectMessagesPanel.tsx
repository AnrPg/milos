"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useEffect, useRef, useState } from "react";

import {
  createDirectThread,
  fetchThreads,
  searchUsers,
  type ChatThread,
} from "@/api/messaging";
import { useSession } from "@/components/session-provider";
import { useChat } from "@/hooks/useChat";
import { useUiPrefs } from "@/stores/ui-prefs";
import { MessageBubble } from "./MessageBubble";
import { MessageComposer } from "./MessageComposer";
import { TypingIndicator } from "./TypingIndicator";
import { SemanticLabel } from "@/components/semantic-label";

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
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!accessToken) return;
    void fetchThreads(accessToken, "direct").then((d) => setThreads(d.threads));
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

  const { messages, typingUsers, sendMessage, sendTypingStart, sendTypingStop } = useChat({
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
      await sendMessage(draft);
      setInput((current) => (current === draft ? "" : current));
      sendTypingStop();
    } catch (error) {
      setSendError(error instanceof Error ? localizeError(error, i18n) : i18n("messageCouldNotBeSent7aa3b0a"));
    } finally {
      setIsSending(false);
    }
  };

  const otherParticipant = (thread: ChatThread) =>
    thread.participants.find((p) => p.user_id !== currentUserId);

  const visibleThreads = threads.filter((t) => !isThreadHidden(currentUserId ?? "", t.id));

  return (
    <div
      className="fixed inset-0 z-[70]"
      style={{ background: "rgba(0,0,0,0.55)" }}
      onClick={onClose}
      role="presentation"
    >
      <aside
        aria-label={i18n("chat2ced57f")}
        className="absolute end-0 top-0 flex h-full w-full max-w-md flex-col overflow-hidden shadow-[-20px_0_60px_rgba(0,0,0,0.5)] rtl:shadow-[20px_0_60px_rgba(0,0,0,0.5)]"
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
                const other = otherParticipant(thread);
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
                        {other?.nickname?.[0]?.toUpperCase() ?? "?"}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium truncate" style={{ color: "var(--text)" }}>
                          {other?.nickname ?? i18n("directMessagefc7f864")}
                        </p>
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
              />
            ))}
            <TypingIndicator typingUsers={typingUsers} />
            <div ref={messagesEndRef} />
          </div>

          <div
            className="p-3 border-t"
            style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}
          >
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
    </div>
  );
}

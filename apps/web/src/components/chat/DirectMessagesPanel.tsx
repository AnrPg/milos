"use client";

import { useEffect, useRef, useState } from "react";

import {
  createDirectThread,
  fetchThreads,
  searchUsers,
  type ChatThread,
} from "@/api/messaging";
import { useSession } from "@/components/session-provider";
import { useChat } from "@/hooks/useChat";
import { MessageBubble } from "./MessageBubble";
import { TypingIndicator } from "./TypingIndicator";

interface SearchResult {
  id: string;
  nickname: string;
  role: string;
}

type PanelView = "list" | "thread";

export function DirectMessagesPanel({ onClose }: { onClose: () => void }) {
  const { tokens, currentUser } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const currentUserId = currentUser?.id ?? null;

  const [view, setView] = useState<PanelView>("list");
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [activeThread, setActiveThread] = useState<ChatThread | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [input, setInput] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!accessToken) return;
    void fetchThreads(accessToken, "direct").then((d) => setThreads(d.threads));
  }, [accessToken]);

  useEffect(() => {
    if (!accessToken || searchQuery.length < 2) return;

    const timeout = setTimeout(() => {
      void searchUsers(accessToken, searchQuery)
        .then((data) =>
          setSearchResults(data.users.filter((u) => u.id !== currentUserId).slice(0, 6)),
        )
        .catch(() => setSearchResults([]));
    }, 300);
    return () => clearTimeout(timeout);
  }, [searchQuery, accessToken, currentUserId]);

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

  const handleSend = () => {
    if (!input.trim()) return;
    sendMessage(input.trim());
    setInput("");
  };

  const otherParticipant = (thread: ChatThread) =>
    thread.participants.find((p) => p.user_id !== currentUserId);

  return (
    <div
      className="fixed right-4 top-14 z-50 rounded-[1.5rem] shadow-2xl flex flex-col overflow-hidden"
      style={{
        width: "340px",
        height: "520px",
        background: "#0d0d18",
        border: "1px solid #2a2a40",
      }}
    >
      {/* Header */}
      <div
        className="flex items-center justify-between px-4 py-3 border-b"
        style={{ borderColor: "#1a1a28" }}
      >
        {view === "thread" ? (
          <button
            type="button"
            onClick={() => setView("list")}
            className="text-sm font-medium flex items-center gap-1"
            style={{ color: "#c8c8e0" }}
          >
            ← Messages
          </button>
        ) : (
          <span className="text-sm font-semibold" style={{ color: "#c8c8e0" }}>
            Messages
          </span>
        )}
        <button
          type="button"
          onClick={onClose}
          className="text-lg leading-none"
          style={{ color: "#55556a" }}
        >
          ✕
        </button>
      </div>

      {view === "list" && (
        <>
          <div className="px-3 py-2 border-b" style={{ borderColor: "#1a1a28" }}>
            <input
              type="text"
              placeholder="Search or start a conversation…"
              className="w-full rounded-[1rem] px-3 py-2 text-sm outline-none"
              style={{ background: "#1a1a28", color: "#e8e8f0", border: "1px solid #2a2a40" }}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          <div className="flex-1 overflow-y-auto">
            {searchResults.length > 0 ? (
              searchResults.map((u) => (
                <button
                  key={u.id}
                  type="button"
                  onClick={() => void startNewThread(u)}
                  className="flex items-center gap-3 w-full px-4 py-3 text-left hover:bg-[#1a1a28] transition-colors"
                >
                  <div
                    className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                    style={{ background: "#2a1a4a", color: "#c5aaf0" }}
                  >
                    {u.nickname[0]?.toUpperCase()}
                  </div>
                  <div>
                    <p className="text-sm font-medium" style={{ color: "#e8e8f0" }}>
                      {u.nickname}
                    </p>
                    <p className="text-xs" style={{ color: "#55556a" }}>
                      {u.role}
                    </p>
                  </div>
                </button>
              ))
            ) : threads.length === 0 ? (
              <p className="text-sm text-center p-4" style={{ color: "#55556a" }}>
                No conversations yet. Search to start one.
              </p>
            ) : (
              threads.map((thread) => {
                const other = otherParticipant(thread);
                return (
                  <button
                    key={thread.id}
                    type="button"
                    onClick={() => openThread(thread)}
                    className="flex items-center gap-3 w-full px-4 py-3 text-left hover:bg-[#1a1a28] transition-colors border-b"
                    style={{ borderColor: "#111120" }}
                  >
                    <div
                      className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                      style={{ background: "#1a1a2e", color: "#9988cc" }}
                    >
                      {other?.user_id?.[0]?.toUpperCase() ?? "?"}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate" style={{ color: "#e8e8f0" }}>
                        {other?.user_id ?? "Direct message"}
                      </p>
                    </div>
                  </button>
                );
              })
            )}
          </div>
        </>
      )}

      {view === "thread" && activeThread && (
        <>
          <div className="flex-1 overflow-y-auto flex flex-col gap-2 p-4">
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
            className="flex items-center gap-2 p-3 border-t"
            style={{ background: "#0d0d18", borderColor: "#1a1a28" }}
          >
            <input
              type="text"
              className="flex-1 rounded-[1rem] px-3 py-2 text-sm outline-none"
              style={{ background: "#1a1a28", color: "#e8e8f0", border: "1px solid #2a2a40" }}
              placeholder="Write a message…"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onFocus={sendTypingStart}
              onBlur={sendTypingStop}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  handleSend();
                }
              }}
            />
            <button
              type="button"
              onClick={handleSend}
              disabled={!input.trim()}
              className="rounded-full px-3 py-2 text-xs font-semibold"
              style={{
                background: "#4f3a7a",
                color: "#f0edf8",
                opacity: input.trim() ? 1 : 0.4,
              }}
            >
              Send
            </button>
          </div>
        </>
      )}
    </div>
  );
}

"use client";

import { useEffect, useRef, useState } from "react";

import { getOrCreateContextThread, type ChatThread, type MessageType } from "@/api/messaging";
import { useSession } from "@/components/session-provider";
import { useChat } from "@/hooks/useChat";
import { MessageBubble } from "./MessageBubble";
import { TypingIndicator } from "./TypingIndicator";

interface ChatSectionProps {
  contextType: "assignment" | "class_slot";
  contextId: string;
  isExpanded: boolean;
  onToggle: () => void;
  readOnly?: boolean;
  participantNicknames?: Record<string, string>;
}

export function ChatSection({
  contextType,
  contextId,
  isExpanded,
  onToggle,
  readOnly = false,
  participantNicknames = {},
}: ChatSectionProps) {
  const { tokens, currentUser } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const currentUserId = currentUser?.id ?? null;

  const [thread, setThread] = useState<ChatThread | null>(null);
  const [threadLoading, setThreadLoading] = useState(false);
  const [input, setInput] = useState("");
  const [messageType] = useState<MessageType>("chat");
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!isExpanded || !accessToken || thread) return;

    let cancelled = false;

    queueMicrotask(() => {
      if (cancelled) return;
      setThreadLoading(true);
      getOrCreateContextThread(accessToken, contextType, contextId)
        .then((data) => {
          if (!cancelled) {
            setThread(data.thread);
            setThreadLoading(false);
          }
        })
        .catch(() => {
          if (!cancelled) setThreadLoading(false);
        });
    });

    return () => {
      cancelled = true;
    };
  }, [isExpanded, accessToken, contextType, contextId, thread]);

  const { messages, typingUsers, isLoading, sendMessage, sendTypingStart, sendTypingStop } =
    useChat({
      threadId: isExpanded ? (thread?.id ?? null) : null,
      accessToken,
      currentUserId,
    });

  useEffect(() => {
    if (isExpanded) {
      messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, isExpanded]);

  const handleSend = () => {
    if (!input.trim()) return;
    sendMessage(input.trim(), messageType);
    setInput("");
  };

  return (
    <div className="flex flex-col border-t" style={{ borderColor: "var(--border)" }}>
      <button
        type="button"
        onClick={onToggle}
        className="flex items-center justify-between w-full px-4 py-3 text-left"
        style={{ background: "var(--panel-muted)" }}
      >
        <span className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
          Conversation
        </span>
        <span style={{ color: "var(--dim)" }}>{isExpanded ? "▲" : "▼"}</span>
      </button>

      {isExpanded && (
        <div className="flex flex-col" style={{ height: "360px" }}>
          <div
            className="flex flex-col gap-2 flex-1 overflow-y-auto p-4"
            style={{ background: "var(--bg)" }}
          >
            {(threadLoading || isLoading) && (
              <p className="text-xs text-center" style={{ color: "var(--dim)" }}>
                Loading…
              </p>
            )}
            {messages.map((msg) => (
              <MessageBubble
                key={msg.id}
                message={msg}
                isOwnMessage={msg.sender_id === currentUserId}
                senderNickname={participantNicknames[msg.sender_id]}
              />
            ))}
            <TypingIndicator typingUsers={typingUsers} />
            <div ref={messagesEndRef} />
          </div>

          {!readOnly && (
            <div
              className="flex items-center gap-2 p-3 border-t"
              style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}
            >
              <input
                type="text"
                className="flex-1 rounded-[1rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--card)", color: "var(--text)", border: "1px solid var(--border-strong)" }}
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
                style={{ background: "var(--primary)", color: "var(--primary-contrast)", opacity: input.trim() ? 1 : 0.4 }}
              >
                Send
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

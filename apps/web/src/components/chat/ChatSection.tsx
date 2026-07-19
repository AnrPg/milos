"use client";




import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";

import { getOrCreateContextThread, type ChatThread, type MessageType } from "@/api/messaging";
import { useSession } from "@/components/session-provider";
import { useChat } from "@/hooks/useChat";
import { MessageBubble } from "./MessageBubble";
import { MessageComposer } from "./MessageComposer";
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
  const i18n = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const currentUserId = currentUser?.id ?? null;

  const [thread, setThread] = useState<ChatThread | null>(null);
  const [threadLoading, setThreadLoading] = useState(false);
  const [input, setInput] = useState("");
  const [messageType] = useState<MessageType>("chat");
  const [isSending, setIsSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
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

  const handleSend = async () => {
    const draft = input;
    if (!draft.trim() || isSending) return;

    setIsSending(true);
    setSendError(null);
    try {
      await sendMessage(draft, messageType);
      setInput((current) => (current === draft ? "" : current));
      sendTypingStop();
    } catch (error) {
      setSendError(error instanceof Error ? error.message : i18n("messageCouldNotBeSent7aa3b0a"));
    } finally {
      setIsSending(false);
    }
  };

  return (
    <div className="flex flex-col border-t" style={{ borderColor: "var(--border)" }}>
      <button
        type="button"
        onClick={onToggle}
        className="flex items-center justify-between w-full px-4 py-3 text-start"
        style={{ background: "var(--panel-muted)" }}
      >
        <span className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
          {i18n("conversation2a20c75")}
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
                {i18n("loading33ce417")}
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
              className="p-3 border-t"
              style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}
            >
              <MessageComposer
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
                error={sendError}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}



import {useUiTranslations} from "@/i18n/ui";
import type { ChatMessage } from "@/api/messaging";

interface MessageBubbleProps {
  message: ChatMessage;
  isOwnMessage: boolean;
  senderNickname?: string;
}

export function MessageBubble({ message, isOwnMessage, senderNickname }: MessageBubbleProps) {
  const i18n = useUiTranslations();
  const isCoachingNote = message.message_type === "coaching_note";
  const time = new Date(message.inserted_at).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });

  return (
    <div
      className={"flex flex-col gap-0.5 max-w-[78%] " + (isOwnMessage ? "self-end items-end" : "self-start items-start")}
    >
      {senderNickname && !isOwnMessage && (
        <span className="text-[10px] font-medium px-1" style={{ color: "var(--muted)" }}>
          {senderNickname}
        </span>
      )}
      <div
        className="whitespace-pre-wrap break-words rounded-2xl px-3 py-2 text-sm leading-relaxed [overflow-wrap:anywhere]"
        data-user-text
        style={
          isOwnMessage
            ? { background: "var(--primary)", color: "var(--primary-contrast)" }
            : { background: "var(--card)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }
        }
      >
        {isCoachingNote && (
          <span
            className="block text-[10px] font-semibold uppercase tracking-widest mb-1"
            style={{ color: isOwnMessage ? "var(--primary-contrast)" : "var(--primary-strong)" }}
          >
            {i18n("coachingNote7e2c608")}
          </span>
        )}
        {message.body}
      </div>
      <span className="text-[10px] px-1" style={{ color: "var(--dim)" }}>
        {time}
      </span>
    </div>
  );
}

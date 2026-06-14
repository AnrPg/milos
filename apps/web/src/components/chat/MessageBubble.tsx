import type { ChatMessage } from "@/api/messaging";

interface MessageBubbleProps {
  message: ChatMessage;
  isOwnMessage: boolean;
  senderNickname?: string;
}

export function MessageBubble({ message, isOwnMessage, senderNickname }: MessageBubbleProps) {
  const isCoachingNote = message.message_type === "coaching_note";
  const time = new Date(message.inserted_at).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });

  return (
    <div
      className={`flex flex-col gap-0.5 max-w-[78%] ${isOwnMessage ? "self-end items-end" : "self-start items-start"}`}
    >
      {senderNickname && !isOwnMessage && (
        <span className="text-[10px] font-medium px-1" style={{ color: "#8888aa" }}>
          {senderNickname}
        </span>
      )}
      <div
        className="rounded-2xl px-3 py-2 text-sm leading-relaxed"
        style={
          isOwnMessage
            ? { background: "#4f3a7a", color: "#f0edf8" }
            : { background: "#1a1a2e", color: "#c8c8e0", border: "1px solid #2a2a40" }
        }
      >
        {isCoachingNote && (
          <span
            className="block text-[10px] font-semibold uppercase tracking-widest mb-1"
            style={{ color: isOwnMessage ? "#c5aaf0" : "#9988cc" }}
          >
            Coaching note
          </span>
        )}
        {message.body}
      </div>
      <span className="text-[10px] px-1" style={{ color: "#55556a" }}>
        {time}
      </span>
    </div>
  );
}

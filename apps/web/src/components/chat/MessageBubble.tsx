

import {useUiTranslations} from "@/i18n/ui";
import type { ChatMessage, MessageTopic } from "@/api/messaging";
import { TOPIC_KEYS } from "./message-topics";
import { OutboxFailureControls } from "@/components/outbox/OutboxFailureControls";
import type { DisplayChatMessage } from "@/lib/offline-message-outbox";

interface MessageBubbleProps {
  message: ChatMessage | DisplayChatMessage;
  isOwnMessage: boolean;
  senderNickname?: string;
  /** Re-enqueue a failed message with its original operation id (ADR-120). */
  onRetry?: (operationId: string) => void | Promise<void>;
  /** Drop a failed message from the device outbox after confirmation. */
  onDiscard?: (operationId: string) => void | Promise<void>;
}

export function MessageBubble({
  message,
  isOwnMessage,
  senderNickname,
  onRetry,
  onDiscard,
}: MessageBubbleProps) {
  const i18n = useUiTranslations();
  // ADR-140 §6: a coaching message and a message from the box are marked;
  // chat is not.
  const topic = "topic" in message ? message.topic : null;
  const kindLabel =
    message.message_type === "coaching_message"
      ? i18n("msgKindCoaching")
      : message.message_type === "box_message"
        ? [i18n("msgKindBox"), topic ? i18n(TOPIC_KEYS[topic as MessageTopic]) : null].filter(Boolean).join(" · ")
        : null;
  const failedOperationId =
    "delivery_status" in message && message.delivery_status === "failed"
      ? (message.client_operation_id ?? null)
      : null;
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
        {kindLabel && (
          <span
            className="block text-[10px] font-semibold uppercase tracking-widest mb-1"
            style={{ color: isOwnMessage ? "var(--primary-contrast)" : "var(--primary-strong)" }}
          >
            {kindLabel}
          </span>
        )}
        {message.body}
      </div>
      <span className="text-[10px] px-1" style={{ color: "var(--dim)" }}>
        {time}
        {"delivery_status" in message && message.delivery_status === "pending"
          ? ` · ${i18n("sendingcf76551")}`
          : ""}
        {"delivery_status" in message && message.delivery_status === "failed"
          ? ` · ${i18n("messageCouldNotBeSent7aa3b0a")}`
          : ""}
      </span>
      {isOwnMessage && failedOperationId && onRetry && onDiscard ? (
        <div className="px-1" role="status">
          <OutboxFailureControls
            align="end"
            failure={"delivery_failure" in message ? message.delivery_failure : undefined}
            confirmKey="outboxDiscardMessageConfirm"
            onRetry={() => onRetry(failedOperationId)}
            onDiscard={() => onDiscard(failedOperationId)}
          />
        </div>
      ) : null}
    </div>
  );
}

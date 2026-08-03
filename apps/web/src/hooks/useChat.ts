"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {useUiTranslations} from "@/i18n/ui";
import { useQueryClient } from "@tanstack/react-query";

import { type ChatMessage, fetchThreadMessages, markThreadRead } from "@/api/messaging";
import {
  deliverQueuedMessage,
  type DisplayChatMessage,
  listQueuedMessageOperations,
  mergeMessagesWithPending,
  notifyOutboxChanged,
  OFFLINE_MESSAGE_OUTBOX_EVENT,
  operationToDisplayMessage,
  queueMessageOperation,
  recordMessageDeliveryFailure,
  removeQueuedMessageOperation,
  type QueuedMessageOperation,
} from "@/lib/offline-message-outbox";
import { joinChannelWithPush } from "@/lib/realtime";

interface TypingUser {
  user_id: string;
  nickname: string;
}

interface UseChatOptions {
  threadId: string | null;
  accessToken: string | null;
  currentUserId: string | null;
}

interface UseChatReturn {
  messages: DisplayChatMessage[];
  typingUsers: TypingUser[];
  isLoading: boolean;
  sendMessage: (body: string, messageType?: string) => Promise<DisplayChatMessage>;
  sendTypingStart: () => void;
  sendTypingStop: () => void;
}

export function useChat({ threadId, accessToken, currentUserId }: UseChatOptions): UseChatReturn {
  const i18n = useUiTranslations();
  const [serverMessages, setServerMessages] = useState<ChatMessage[]>([]);
  const [queuedMessages, setQueuedMessages] = useState<QueuedMessageOperation[]>([]);
  const [typingUsers, setTypingUsers] = useState<TypingUser[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const queryClient = useQueryClient();

  const channelRef = useRef<ReturnType<typeof joinChannelWithPush> | null>(null);
  const messages = useMemo(
    () => mergeMessagesWithPending(serverMessages, queuedMessages),
    [queuedMessages, serverMessages],
  );

  const invalidateUnreadCount = useCallback(() => {
    void queryClient.invalidateQueries({ queryKey: ["messages", "unread"] });
  }, [queryClient]);

  // Load initial history via REST and mark existing messages as read
  useEffect(() => {
    if (!threadId || !accessToken) return;

    let cancelled = false;

    queueMicrotask(() => {
      if (cancelled) return;
      setIsLoading(true);
      Promise.allSettled([
        fetchThreadMessages(accessToken, threadId),
        currentUserId ? listQueuedMessageOperations(currentUserId, threadId) : Promise.resolve([]),
      ])
        .then(([serverResult, queueResult]) => {
          if (!cancelled) {
            const data = serverResult.status === "fulfilled" ? serverResult.value : null;
            const queued = queueResult.status === "fulfilled" ? queueResult.value : [];
            if (data) setServerMessages(data.messages);
            setQueuedMessages(queued);
            setIsLoading(false);
            const lastMessage = data?.messages.at(-1);
            if (lastMessage) {
              void markThreadRead(accessToken, threadId, lastMessage.id).then(invalidateUnreadCount);
            }
          }
        })
        .catch(() => {
          if (!cancelled) setIsLoading(false);
        });
    });

    return () => {
      cancelled = true;
    };
  }, [threadId, accessToken, currentUserId, invalidateUnreadCount]);

  useEffect(() => {
    if (!threadId || !currentUserId) return;

    const refreshQueued = (event: Event) => {
      const detail = (event as CustomEvent<{ message: ChatMessage | null }>).detail;
      const deliveredMessage = detail?.message;
      if (deliveredMessage?.thread_id === threadId) {
        setServerMessages((previous) => upsertServerMessage(previous, deliveredMessage));
      }
      void listQueuedMessageOperations(currentUserId, threadId).then(setQueuedMessages);
    };

    window.addEventListener(OFFLINE_MESSAGE_OUTBOX_EVENT, refreshQueued);
    return () => window.removeEventListener(OFFLINE_MESSAGE_OUTBOX_EVENT, refreshQueued);
  }, [currentUserId, threadId]);

  // Connect Phoenix Channel
  useEffect(() => {
    if (!threadId || !accessToken) return;

    const channel = joinChannelWithPush(accessToken, `chat:thread:${threadId}`, {
      new_message: (payload) => {
        const message = payload as ChatMessage;
        setServerMessages((previous) => upsertServerMessage(previous, message));
        if (message.sender_id !== currentUserId && accessToken) {
          void markThreadRead(accessToken, threadId, message.id).then(invalidateUnreadCount);
        }
      },
      typing: (payload) => {
        const { user_id, nickname, typing } = payload as {
          user_id: string;
          nickname: string;
          typing: boolean;
        };
        if (user_id === currentUserId) return;
        setTypingUsers((prev) =>
          typing
            ? prev.some((u) => u.user_id === user_id)
              ? prev
              : [...prev, { user_id, nickname }]
            : prev.filter((u) => u.user_id !== user_id),
        );
      },
    });

    channelRef.current = channel;

    return () => {
      channel.leave();
      channelRef.current = null;
    };
  }, [threadId, accessToken, currentUserId, invalidateUnreadCount]);

  const sendMessage = useCallback(
    async (body: string, messageType = "chat") => {
      if (!threadId || !accessToken || !currentUserId) {
        throw new Error(i18n("chatDisconnectedError"));
      }

      const operation = await queueMessageOperation(
        currentUserId,
        threadId,
        body,
        messageType as QueuedMessageOperation["messageType"],
      );
      setQueuedMessages((previous) => [...previous, operation]);

      if (!navigator.onLine) return operationToDisplayMessage(operation);

      try {
        const delivered = await deliverQueuedMessage(accessToken, operation);
        await removeQueuedMessageOperation(operation.operationId);
        setQueuedMessages((previous) =>
          previous.filter((item) => item.operationId !== operation.operationId),
        );
        setServerMessages((previous) => upsertServerMessage(previous, delivered));
        notifyOutboxChanged(delivered);
        return { ...delivered, delivery_status: "sent" as const };
      } catch (error) {
        const updated = await recordMessageDeliveryFailure(operation, error);
        setQueuedMessages((previous) =>
          previous.map((item) => (item.operationId === updated.operationId ? updated : item)),
        );
        return operationToDisplayMessage(updated);
      }
    },
    [accessToken, currentUserId, i18n, threadId],
  );

  const sendTypingStart = useCallback(() => {
    void channelRef.current?.push<{ typing: boolean }>("typing_start", {}).catch(() => undefined);
  }, []);

  const sendTypingStop = useCallback(() => {
    void channelRef.current?.push<{ typing: boolean }>("typing_stop", {}).catch(() => undefined);
  }, []);

  return { messages, typingUsers, isLoading, sendMessage, sendTypingStart, sendTypingStop };
}

function upsertServerMessage(messages: ChatMessage[], incoming: ChatMessage) {
  const operationId =
    "client_operation_id" in incoming ? incoming.client_operation_id : undefined;
  const withoutDuplicate = messages.filter(
    (message) =>
      message.id !== incoming.id &&
      (!operationId ||
        !("client_operation_id" in message) ||
        message.client_operation_id !== operationId),
  );
  return [...withoutDuplicate, incoming];
}

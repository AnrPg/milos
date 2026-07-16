"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

import { type ChatMessage, fetchThreadMessages, markThreadRead } from "@/api/messaging";
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
  messages: ChatMessage[];
  typingUsers: TypingUser[];
  isLoading: boolean;
  sendMessage: (body: string, messageType?: string) => Promise<ChatMessage>;
  sendTypingStart: () => void;
  sendTypingStop: () => void;
}

export function useChat({ threadId, accessToken, currentUserId }: UseChatOptions): UseChatReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [typingUsers, setTypingUsers] = useState<TypingUser[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const queryClient = useQueryClient();

  const channelRef = useRef<ReturnType<typeof joinChannelWithPush> | null>(null);

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
      fetchThreadMessages(accessToken, threadId)
        .then((data) => {
          if (!cancelled) {
            setMessages(data.messages);
            setIsLoading(false);
            const lastMessage = data.messages.at(-1);
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
  }, [threadId, accessToken, invalidateUnreadCount]);

  // Connect Phoenix Channel
  useEffect(() => {
    if (!threadId || !accessToken) return;

    const channel = joinChannelWithPush(accessToken, `chat:thread:${threadId}`, {
      new_message: (payload) => {
        const message = payload as ChatMessage;
        setMessages((prev) => {
          if (prev.some((m) => m.id === message.id)) return prev;
          return [...prev, message];
        });
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

  const sendMessage = useCallback(async (body: string, messageType = "chat") => {
    const channel = channelRef.current;
    if (!channel) throw new Error("Chat is disconnected. Your message was not sent.");

    return channel.push<ChatMessage>("send_message", { body, message_type: messageType });
  }, []);

  const sendTypingStart = useCallback(() => {
    void channelRef.current?.push<{ typing: boolean }>("typing_start", {}).catch(() => undefined);
  }, []);

  const sendTypingStop = useCallback(() => {
    void channelRef.current?.push<{ typing: boolean }>("typing_stop", {}).catch(() => undefined);
  }, []);

  return { messages, typingUsers, isLoading, sendMessage, sendTypingStart, sendTypingStop };
}

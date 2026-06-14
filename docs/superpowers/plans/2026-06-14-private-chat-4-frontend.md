# Private Chat — Plan 4: Frontend

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all frontend surfaces: API client, Phoenix Channel hook, ChatSection accordion component, side panel integration, DirectMessagesPanel (TopNav floating panel), Account Activity Chats page, and Notification Messages chip.

**Architecture:** Next.js 15 app router. New `apps/web/src/components/chat/` component family. Phoenix Channel connection via `phoenix` npm package. No new routing lib — uses `app/` directory conventions.

**Tech Stack:** Next.js 15, TypeScript, Tailwind CSS, `phoenix` npm package (already in deps for notifications/sync channels)

**Depends on:** Plans 1–3 (backend API and Channel must be running)

**IMPORTANT:** Read `apps/web/node_modules/next/dist/docs/` before touching Next.js routing — per `AGENTS.md`, this version may differ from training data.

---

## File Map

### New files
- `apps/web/src/api/messaging.ts`
- `apps/web/src/hooks/useChat.ts`
- `apps/web/src/components/chat/MessageBubble.tsx`
- `apps/web/src/components/chat/TypingIndicator.tsx`
- `apps/web/src/components/chat/ChatSection.tsx`
- `apps/web/src/components/chat/DirectMessagesPanel.tsx`
- `apps/web/src/app/account/activity/chats/page.tsx`

### Modified files
- `apps/web/src/components/workouts/AssignedWorkoutPanel.tsx` — replace messages section with accordion + ChatSection
- `apps/web/src/components/TopNav.tsx` — add Messages icon + DirectMessagesPanel
- `apps/web/src/components/notifications/NotificationBell.tsx` — add Messages chip filter

---

## Task 1: messaging.ts API client

**Files:**
- Create: `apps/web/src/api/messaging.ts`

- [ ] **Step 1: Check existing API client pattern**

```bash
cat apps/web/src/api/client.ts | head -30
```

Use the same `apiRequest` wrapper seen in `finance.ts`.

- [ ] **Step 2: Write messaging.ts**

```typescript
// apps/web/src/api/messaging.ts
import { apiRequest } from "@/api/client";

export type MessageType = "text" | "coaching_note";

export interface ChatParticipant {
  user_id: string;
  last_read_message_id: string | null;
  joined_at: string;
}

export interface ChatThread {
  id: string;
  context_type: "direct" | "assignment" | "class_slot";
  context_id: string | null;
  inserted_at: string;
  participants: ChatParticipant[];
}

export interface ChatMessage {
  id: string;
  thread_id: string;
  sender_id: string;
  body: string;
  message_type: MessageType;
  inserted_at: string;
}

export type ThreadContextType = "direct" | "assignment" | "class_slot";

export async function fetchThreads(token: string, contextType?: ThreadContextType) {
  const qs = contextType ? `?context_type=${contextType}` : "";
  return apiRequest<{ threads: ChatThread[] }>(`/threads${qs}`, { token });
}

export async function createDirectThread(token: string, participantId: string) {
  return apiRequest<{ thread: ChatThread }>("/threads", {
    method: "POST",
    token,
    body: { participant_id: participantId },
  });
}

export async function fetchContextThread(
  token: string,
  contextType: "assignment" | "class_slot",
  contextId: string,
) {
  return apiRequest<{ thread: ChatThread }>(
    `/threads/context/${contextType}/${contextId}`,
    { token },
  );
}

export async function fetchThreadMessages(
  token: string,
  threadId: string,
  params: { limit?: number; cursor_inserted_at?: string } = {},
) {
  const qs = new URLSearchParams(
    Object.entries(params)
      .filter(([, v]) => v !== undefined)
      .map(([k, v]) => [k, String(v)]),
  ).toString();

  return apiRequest<{ messages: ChatMessage[] }>(
    `/threads/${threadId}/messages${qs ? `?${qs}` : ""}`,
    { token },
  );
}

export async function sendMessage(
  token: string,
  threadId: string,
  body: string,
  messageType: MessageType = "text",
) {
  return apiRequest<{ message: ChatMessage }>(`/threads/${threadId}/messages`, {
    method: "POST",
    token,
    body: { body, message_type: messageType },
  });
}

export async function markThreadRead(
  token: string,
  threadId: string,
  lastMessageId: string,
) {
  return apiRequest<{ read: boolean }>(`/threads/${threadId}/read`, {
    method: "POST",
    token,
    body: { last_message_id: lastMessageId },
  });
}

export async function searchUsers(token: string, query: string) {
  // Reuses existing admin search endpoint
  return apiRequest<{ users: { id: string; nickname: string; role: string }[] }>(
    `/admin/search?q=${encodeURIComponent(query)}`,
    { token },
  );
}
```

- [ ] **Step 3: Type-check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -20
```

Expected: no errors in `messaging.ts`.

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/api/messaging.ts
git commit -m "feat(web/messaging): messaging API client"
```

---

## Task 2: useChat hook (Phoenix Channel)

**Files:**
- Create: `apps/web/src/hooks/useChat.ts`

- [ ] **Step 1: Check how existing channels are connected**

```bash
grep -r "Channel\|socket\|phoenix" apps/web/src/hooks/ apps/web/src/lib/ --include="*.ts" --include="*.tsx" -l | head -5
```

Find the existing Phoenix socket/channel setup pattern used for notifications or execution channels.

- [ ] **Step 2: Write useChat hook**

```typescript
// apps/web/src/hooks/useChat.ts
"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Channel, Socket } from "phoenix";

import { type ChatMessage, fetchThreadMessages, markThreadRead } from "@/api/messaging";

interface TypingUser {
  user_id: string;
  nickname: string;
}

interface UseChatOptions {
  threadId: string | null;
  accessToken: string | null;
  currentUserId: string | null;
  socketUrl: string;
}

interface UseChatReturn {
  messages: ChatMessage[];
  typingUsers: TypingUser[];
  isLoading: boolean;
  sendMessage: (body: string, messageType?: string) => void;
  sendTypingStart: () => void;
  sendTypingStop: () => void;
}

export function useChat({
  threadId,
  accessToken,
  currentUserId,
  socketUrl,
}: UseChatOptions): UseChatReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [typingUsers, setTypingUsers] = useState<TypingUser[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const channelRef = useRef<Channel | null>(null);
  const socketRef = useRef<Socket | null>(null);

  // Load initial history via REST
  useEffect(() => {
    if (!threadId || !accessToken) return;

    setIsLoading(true);
    fetchThreadMessages(accessToken, threadId)
      .then((data) => {
        setMessages(data.messages);
        setIsLoading(false);
      })
      .catch(() => setIsLoading(false));
  }, [threadId, accessToken]);

  // Connect Phoenix Channel
  useEffect(() => {
    if (!threadId || !accessToken) return;

    const socket = new Socket(socketUrl, { params: { token: accessToken } });
    socket.connect();
    socketRef.current = socket;

    const channel = socket.channel(`chat:thread:${threadId}`, {});
    channelRef.current = channel;

    channel.on("new_message", (message: ChatMessage) => {
      setMessages((prev) => [...prev, message]);

      // Auto-mark read if it's from someone else
      if (message.sender_id !== currentUserId && accessToken) {
        void markThreadRead(accessToken, threadId, message.id);
      }
    });

    channel.on("typing", ({ user_id, nickname, typing }: { user_id: string; nickname: string; typing: boolean }) => {
      if (user_id === currentUserId) return;
      setTypingUsers((prev) =>
        typing
          ? prev.some((u) => u.user_id === user_id)
            ? prev
            : [...prev, { user_id, nickname }]
          : prev.filter((u) => u.user_id !== user_id),
      );
    });

    channel.join();

    return () => {
      channel.leave();
      socket.disconnect();
      channelRef.current = null;
      socketRef.current = null;
    };
  }, [threadId, accessToken, currentUserId, socketUrl]);

  const sendMessage = useCallback((body: string, messageType = "text") => {
    channelRef.current?.push("send_message", { body, message_type: messageType });
  }, []);

  const sendTypingStart = useCallback(() => {
    channelRef.current?.push("typing_start", {});
  }, []);

  const sendTypingStop = useCallback(() => {
    channelRef.current?.push("typing_stop", {});
  }, []);

  return { messages, typingUsers, isLoading, sendMessage, sendTypingStart, sendTypingStop };
}
```

- [ ] **Step 3: Type-check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | grep "useChat" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/hooks/useChat.ts
git commit -m "feat(web/messaging): useChat Phoenix Channel hook"
```

---

## Task 3: MessageBubble + TypingIndicator components

**Files:**
- Create: `apps/web/src/components/chat/MessageBubble.tsx`
- Create: `apps/web/src/components/chat/TypingIndicator.tsx`

- [ ] **Step 1: Write MessageBubble**

```tsx
// apps/web/src/components/chat/MessageBubble.tsx
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
```

- [ ] **Step 2: Write TypingIndicator**

```tsx
// apps/web/src/components/chat/TypingIndicator.tsx
interface TypingUser {
  user_id: string;
  nickname: string;
}

interface TypingIndicatorProps {
  typingUsers: TypingUser[];
}

export function TypingIndicator({ typingUsers }: TypingIndicatorProps) {
  if (typingUsers.length === 0) return null;

  const label =
    typingUsers.length === 1
      ? `${typingUsers[0].nickname} is typing…`
      : `${typingUsers.map((u) => u.nickname).join(", ")} are typing…`;

  return (
    <div className="flex items-center gap-2 px-1 py-0.5">
      <div className="flex gap-0.5">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="block w-1.5 h-1.5 rounded-full"
            style={{
              background: "#7755aa",
              animation: `bounce 1.2s ease-in-out ${i * 0.2}s infinite`,
            }}
          />
        ))}
      </div>
      <span className="text-[11px]" style={{ color: "#8888aa" }}>
        {label}
      </span>
    </div>
  );
}
```

- [ ] **Step 3: Type-check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | grep -E "MessageBubble|TypingIndicator" | head -10
```

---

## Task 4: ChatSection accordion component

**Files:**
- Create: `apps/web/src/components/chat/ChatSection.tsx`

- [ ] **Step 1: Check how to get the API base URL and session in components**

```bash
grep -r "NEXT_PUBLIC\|socketUrl\|WS_URL" apps/web/src/ --include="*.ts" --include="*.tsx" | head -5
grep -r "useSession\|session-provider" apps/web/src/hooks/ --include="*.ts" | head -5
```

- [ ] **Step 2: Write ChatSection**

```tsx
// apps/web/src/components/chat/ChatSection.tsx
"use client";

import { useEffect, useRef, useState } from "react";

import { fetchContextThread, type ChatThread, type MessageType } from "@/api/messaging";
import { useSession } from "@/components/session-provider";
import { useChat } from "@/hooks/useChat";
import { MessageBubble } from "./MessageBubble";
import { TypingIndicator } from "./TypingIndicator";

const SOCKET_URL =
  process.env.NEXT_PUBLIC_WS_URL ?? "ws://localhost:4000/socket";

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
  const { tokens, user } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const currentUserId = user?.id ?? null;

  const [thread, setThread] = useState<ChatThread | null>(null);
  const [threadLoading, setThreadLoading] = useState(false);
  const [input, setInput] = useState("");
  const [messageType, setMessageType] = useState<MessageType>("text");
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Resolve or create thread when expanded
  useEffect(() => {
    if (!isExpanded || !accessToken || thread) return;

    setThreadLoading(true);
    fetchContextThread(accessToken, contextType, contextId)
      .then((data) => {
        setThread(data.thread);
        setThreadLoading(false);
      })
      .catch(() => setThreadLoading(false));
  }, [isExpanded, accessToken, contextType, contextId, thread]);

  const { messages, typingUsers, isLoading, sendMessage, sendTypingStart, sendTypingStop } =
    useChat({
      threadId: isExpanded ? (thread?.id ?? null) : null,
      accessToken,
      currentUserId,
      socketUrl: SOCKET_URL,
    });

  // Scroll to bottom on new messages
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

  const unreadCount = 0; // TODO: compute from messages vs last_read_message_id

  return (
    <div className="flex flex-col border-t" style={{ borderColor: "#1a1a28" }}>
      {/* Section header — always visible */}
      <button
        type="button"
        onClick={onToggle}
        className="flex items-center justify-between w-full px-4 py-3 text-left"
        style={{ background: "#0d0d18" }}
      >
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium" style={{ color: "#c8c8e0" }}>
            💬 Conversation
          </span>
          {!isExpanded && unreadCount > 0 && (
            <span
              className="text-[10px] font-bold px-1.5 py-0.5 rounded-full"
              style={{ background: "#e07a5f", color: "#fff" }}
            >
              {unreadCount}
            </span>
          )}
        </div>
        <span style={{ color: "#55556a" }}>{isExpanded ? "▲" : "▼"}</span>
      </button>

      {/* Expanded content */}
      {isExpanded && (
        <div className="flex flex-col" style={{ height: "360px" }}>
          {/* Message list */}
          <div
            className="flex flex-col gap-2 flex-1 overflow-y-auto p-4"
            style={{ background: "#07070f" }}
          >
            {(threadLoading || isLoading) && (
              <p className="text-xs text-center" style={{ color: "#55556a" }}>
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

          {/* Input */}
          {!readOnly && (
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
                style={{ background: "#4f3a7a", color: "#f0edf8", opacity: input.trim() ? 1 : 0.4 }}
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
```

- [ ] **Step 3: Type-check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | grep "ChatSection" | head -10
```

- [ ] **Step 4: Commit components**

```bash
git add apps/web/src/components/chat/ apps/web/src/hooks/useChat.ts apps/web/src/api/messaging.ts
git commit -m "feat(web/messaging): ChatSection accordion, MessageBubble, TypingIndicator, useChat hook"
```

---

## Task 5: Integrate accordion into AssignedWorkoutPanel

**Files:**
- Modify: `apps/web/src/components/workouts/AssignedWorkoutPanel.tsx`

- [ ] **Step 1: Read current panel structure**

```bash
grep -n "messages\|Message\|section\|collapse" apps/web/src/components/workouts/AssignedWorkoutPanel.tsx | head -30
```

- [ ] **Step 2: Add accordion state and replace messages section**

At the top of the component, add accordion state:

```tsx
const [openSection, setOpenSection] = useState<"details" | "chat">("details");
```

Replace the existing messages section (the `{/* Conversation with athlete */}` block and everything around it) with:

```tsx
{/* Accordion: Details */}
<button
  type="button"
  onClick={() => setOpenSection("details")}
  className="flex items-center justify-between w-full px-4 py-3 text-left border-b"
  style={{ background: "#0d0d18", borderColor: "#1a1a28" }}
>
  <span className="text-sm font-medium" style={{ color: "#c8c8e0" }}>📋 Details</span>
  <span style={{ color: "#55556a" }}>{openSection === "details" ? "▲" : "▼"}</span>
</button>

{openSection === "details" && (
  <div className="p-4 space-y-4">
    {/* existing details content here — move it inside */}
  </div>
)}

{/* Accordion: Conversation */}
<ChatSection
  contextType="assignment"
  contextId={assignment.id}
  isExpanded={openSection === "chat"}
  onToggle={() => setOpenSection(openSection === "chat" ? "details" : "chat")}
  participantNicknames={
    isAdmin
      ? { [assignment.athlete_id ?? ""]: assignment.athlete_nickname ?? "" }
      : {}
  }
/>
```

Add import at the top:

```tsx
import { ChatSection } from "@/components/chat/ChatSection";
```

Remove old message-related state and functions:
- `const [messages, setMessages]`
- `const [messageText, setMessageText]`
- `const [messageSending, setMessageSending]`
- `const [messageError, setMessageError]`
- `const messagesEndRef`
- `handleSendMessage()`
- `fetchAssignmentMessages(...)` calls

Remove imports: `fetchAssignmentMessages`, `postAssignmentMessage`, `AssignmentMessage` from `@/api/...`

- [ ] **Step 3: Type-check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | grep "AssignedWorkoutPanel" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/workouts/AssignedWorkoutPanel.tsx
git commit -m "feat(web/messaging): replace assignment messages with ChatSection accordion"
```

---

## Task 6: DirectMessagesPanel + TopNav badge

**Files:**
- Create: `apps/web/src/components/chat/DirectMessagesPanel.tsx`
- Modify: `apps/web/src/components/TopNav.tsx`

- [ ] **Step 1: Write DirectMessagesPanel**

```tsx
// apps/web/src/components/chat/DirectMessagesPanel.tsx
"use client";

import { useEffect, useRef, useState } from "react";

import {
  createDirectThread,
  fetchThreadMessages,
  fetchThreads,
  searchUsers,
  type ChatMessage,
  type ChatThread,
} from "@/api/messaging";
import { useSession } from "@/components/session-provider";
import { useChat } from "@/hooks/useChat";
import { MessageBubble } from "./MessageBubble";
import { TypingIndicator } from "./TypingIndicator";

const SOCKET_URL = process.env.NEXT_PUBLIC_WS_URL ?? "ws://localhost:4000/socket";

interface SearchResult {
  id: string;
  nickname: string;
  role: string;
}

type PanelView = "list" | "thread";

export function DirectMessagesPanel({ onClose }: { onClose: () => void }) {
  const { tokens, user } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const currentUserId = user?.id ?? null;

  const [view, setView] = useState<PanelView>("list");
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [activeThread, setActiveThread] = useState<ChatThread | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [input, setInput] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Load direct threads
  useEffect(() => {
    if (!accessToken) return;
    void fetchThreads(accessToken, "direct").then((d) => setThreads(d.threads));
  }, [accessToken]);

  // Search users as they type
  useEffect(() => {
    if (!accessToken || searchQuery.length < 2) {
      setSearchResults([]);
      return;
    }
    const timeout = setTimeout(async () => {
      try {
        const data = await searchUsers(accessToken, searchQuery);
        setSearchResults(data.users.filter((u) => u.id !== currentUserId).slice(0, 6));
      } catch {
        setSearchResults([]);
      }
    }, 300);
    return () => clearTimeout(timeout);
  }, [searchQuery, accessToken, currentUserId]);

  const { messages, typingUsers, sendMessage, sendTypingStart, sendTypingStop } = useChat({
    threadId: view === "thread" ? (activeThread?.id ?? null) : null,
    accessToken,
    currentUserId,
    socketUrl: SOCKET_URL,
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
    setThreads((prev) =>
      prev.some((t) => t.id === thread.id) ? prev : [thread, ...prev],
    );
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
          {/* Search */}
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

          {/* Search results or thread list */}
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
                      ?
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
          {/* Messages */}
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

          {/* Input */}
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
```

- [ ] **Step 2: Add Messages icon to TopNav**

In `apps/web/src/components/TopNav.tsx`, add:

```tsx
// At the top, add state:
const [showMessages, setShowMessages] = useState(false);

// Add import:
import { DirectMessagesPanel } from "@/components/chat/DirectMessagesPanel";

// In the JSX, next to the notification bell, add:
<div className="relative">
  <button
    type="button"
    onClick={() => setShowMessages((v) => !v)}
    className="relative p-2 rounded-full"
    style={{ color: "#c8c8e0" }}
    aria-label="Messages"
  >
    {/* Message square icon */}
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    </svg>
    {/* Unread badge — wire to real count in a follow-up */}
  </button>

  {showMessages && (
    <DirectMessagesPanel onClose={() => setShowMessages(false)} />
  )}
</div>
```

- [ ] **Step 3: Type-check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | grep -E "DirectMessages|TopNav" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/chat/DirectMessagesPanel.tsx \
        apps/web/src/components/TopNav.tsx
git commit -m "feat(web/messaging): DirectMessagesPanel floating overlay + TopNav Messages icon"
```

---

## Task 7: Account Activity Chats page (read-only)

**Files:**
- Create: `apps/web/src/app/account/activity/chats/page.tsx`

- [ ] **Step 1: Check if account/activity directory exists**

```bash
ls apps/web/src/app/account/ 2>/dev/null || echo "does not exist"
```

Create parent directories as needed. Check Next.js docs in `node_modules/next/dist/docs/` for layout/page conventions before writing.

- [ ] **Step 2: Write the page**

```tsx
// apps/web/src/app/account/activity/chats/page.tsx
"use client";

import { useEffect, useState } from "react";

import {
  fetchContextThread,
  fetchThreadMessages,
  fetchThreads,
  type ChatMessage,
  type ChatThread,
  type ThreadContextType,
} from "@/api/messaging";
import { useSession } from "@/components/session-provider";
import { MessageBubble } from "@/components/chat/MessageBubble";

type Tab = "direct" | "assignment" | "class_slot";

const ROLE_TABS: Record<string, Tab[]> = {
  admin: ["direct", "assignment", "class_slot"],
  coach: ["direct", "assignment", "class_slot"],
  athlete: ["direct", "assignment"],
  member: ["direct", "class_slot"],
};

const TAB_LABELS: Record<Tab, string> = {
  direct: "Direct",
  assignment: "Workout",
  class_slot: "Class",
};

export default function ChatsPage() {
  const { tokens, user } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const role = (user as { role?: string })?.role ?? "member";
  const currentUserId = user?.id ?? null;

  const availableTabs: Tab[] = ROLE_TABS[role] ?? ["direct"];
  const [activeTab, setActiveTab] = useState<Tab>(availableTabs[0]);
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [selectedThread, setSelectedThread] = useState<ChatThread | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loadingThreads, setLoadingThreads] = useState(true);
  const [loadingMessages, setLoadingMessages] = useState(false);

  useEffect(() => {
    if (!accessToken) return;
    setLoadingThreads(true);
    setSelectedThread(null);
    setMessages([]);

    fetchThreads(accessToken, activeTab as ThreadContextType)
      .then((d) => {
        setThreads(d.threads);
        setLoadingThreads(false);
      })
      .catch(() => setLoadingThreads(false));
  }, [accessToken, activeTab]);

  const openThread = async (thread: ChatThread) => {
    if (!accessToken) return;
    setSelectedThread(thread);
    setLoadingMessages(true);
    try {
      const data = await fetchThreadMessages(accessToken, thread.id);
      setMessages(data.messages);
    } finally {
      setLoadingMessages(false);
    }
  };

  return (
    <div className="flex flex-col h-full min-h-screen" style={{ background: "#07070f" }}>
      <div className="max-w-4xl mx-auto w-full px-4 py-8 flex flex-col gap-6">
        <h1 className="text-xl font-semibold" style={{ color: "#e8e8f0" }}>
          Conversation History
        </h1>

        {/* Role-based tabs */}
        <div
          className="flex rounded-full p-0.5 gap-0.5"
          style={{ background: "#1a1a28", width: "fit-content" }}
        >
          {availableTabs.map((tab) => (
            <button
              key={tab}
              type="button"
              onClick={() => setActiveTab(tab)}
              className="rounded-full px-4 py-1.5 text-sm font-semibold"
              style={
                activeTab === tab
                  ? { background: "#F0EDF8", color: "#0A0A0F" }
                  : { color: "#55556a" }
              }
            >
              {TAB_LABELS[tab]}
            </button>
          ))}
        </div>

        <div className="flex gap-4" style={{ minHeight: "480px" }}>
          {/* Thread list */}
          <div
            className="flex flex-col rounded-[1.5rem] overflow-hidden flex-shrink-0"
            style={{ width: "220px", background: "#0d0d18", border: "1px solid #1a1a28" }}
          >
            {loadingThreads ? (
              <p className="text-sm p-4" style={{ color: "#55556a" }}>
                Loading…
              </p>
            ) : threads.length === 0 ? (
              <p className="text-sm p-4" style={{ color: "#55556a" }}>
                No conversations.
              </p>
            ) : (
              threads.map((thread) => (
                <button
                  key={thread.id}
                  type="button"
                  onClick={() => void openThread(thread)}
                  className="flex flex-col gap-0.5 px-4 py-3 text-left border-b transition-colors hover:bg-[#1a1a28]"
                  style={{
                    borderColor: "#111120",
                    background: selectedThread?.id === thread.id ? "#1a1a28" : "transparent",
                  }}
                >
                  <span className="text-xs font-medium truncate" style={{ color: "#c8c8e0" }}>
                    {thread.context_type === "direct"
                      ? "Direct"
                      : `${thread.context_type} thread`}
                  </span>
                  <span className="text-[10px]" style={{ color: "#55556a" }}>
                    {new Date(thread.inserted_at).toLocaleDateString()}
                  </span>
                </button>
              ))
            )}
          </div>

          {/* Message detail */}
          <div
            className="flex flex-col flex-1 rounded-[1.5rem] overflow-hidden"
            style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
          >
            {!selectedThread ? (
              <div className="flex items-center justify-center flex-1">
                <p className="text-sm" style={{ color: "#55556a" }}>
                  Select a conversation to view messages.
                </p>
              </div>
            ) : loadingMessages ? (
              <div className="flex items-center justify-center flex-1">
                <p className="text-sm" style={{ color: "#55556a" }}>
                  Loading…
                </p>
              </div>
            ) : (
              <div className="flex flex-col gap-2 flex-1 overflow-y-auto p-4">
                {messages.map((msg) => (
                  <MessageBubble
                    key={msg.id}
                    message={msg}
                    isOwnMessage={msg.sender_id === currentUserId}
                  />
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Type-check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | grep "chats" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/app/account/
git commit -m "feat(web/messaging): Account Activity Chats read-only history page"
```

---

## Task 8: Notification Messages chip

**Files:**
- Modify: `apps/web/src/components/notifications/NotificationBell.tsx`

- [ ] **Step 1: Read current NotificationBell structure**

```bash
cat apps/web/src/components/notifications/NotificationBell.tsx | head -80
```

- [ ] **Step 2: Add Messages filter chip**

Find where the notification type filter chips are rendered. If there are existing type filter chips, add `Messages` alongside them. If no filter chips exist yet, add a chip bar below the inbox header:

```tsx
// Add to chip state and logic:
type NotifFilter = "all" | "messages" | string; // extend existing filter type

// Add chip:
<button
  type="button"
  onClick={() => setFilter("messages")}
  className="rounded-full px-3 py-1 text-xs font-semibold"
  style={
    filter === "messages"
      ? { background: "#4f3a7a", color: "#f0edf8" }
      : { background: "#1a1a28", color: "#55556a" }
  }
>
  Messages
</button>

// Filter logic: when filter === "messages", show only notifications where n.type === "chat_message"
const filteredNotifications =
  filter === "messages"
    ? notifications.filter((n) => n.type === "chat_message")
    : filter === "all"
    ? notifications
    : notifications.filter((n) => n.type === filter);
```

Adjust the exact integration to match the existing chip pattern in `NotificationBell.tsx`.

- [ ] **Step 3: Type-check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | grep "NotificationBell" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/notifications/NotificationBell.tsx
git commit -m "feat(web/messaging): Messages chip filter in notification inbox"
```

---

## Task 9: Final verification

- [ ] **Step 1: TypeScript full check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | tail -10
```

Expected: `Found 0 errors.`

- [ ] **Step 2: Lint**

```bash
cd apps/web && npm run lint 2>&1 | tail -10
```

Expected: no new lint errors.

- [ ] **Step 3: Backend tests still pass**

```bash
cd apps/api && mix test 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 4: Final commit**

```bash
git add -A
git status  # verify only intended files
git commit -m "feat(messaging): complete private chat frontend implementation"
```

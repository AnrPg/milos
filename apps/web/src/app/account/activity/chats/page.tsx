"use client";

import { useEffect, useState } from "react";

import {
  fetchThreadMessages,
  fetchThreads,
  type ChatMessage,
  type ChatThread,
  type ThreadContextType,
} from "@/api/messaging";
import { MessageBubble } from "@/components/chat/MessageBubble";
import { useSession } from "@/components/session-provider";

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
  const { tokens, currentUser } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const role = (currentUser as { role?: string } | null)?.role ?? "member";
  const currentUserId = currentUser?.id ?? null;

  const availableTabs: Tab[] = ROLE_TABS[role] ?? ["direct"];
  const [activeTab, setActiveTab] = useState<Tab>(availableTabs[0]!);
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [selectedThread, setSelectedThread] = useState<ChatThread | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loadingThreads, setLoadingThreads] = useState(true);
  const [loadingMessages, setLoadingMessages] = useState(false);

  useEffect(() => {
    if (!accessToken) return;

    let cancelled = false;

    queueMicrotask(() => {
      if (cancelled) return;
      setLoadingThreads(true);
      setSelectedThread(null);
      setMessages([]);

      fetchThreads(accessToken, activeTab as ThreadContextType)
        .then((d) => {
          if (!cancelled) {
            setThreads(d.threads);
            setLoadingThreads(false);
          }
        })
        .catch(() => {
          if (!cancelled) setLoadingThreads(false);
        });
    });

    return () => {
      cancelled = true;
    };
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
                    {thread.context_type === "direct" ? "Direct" : `${thread.context_type} thread`}
                  </span>
                  <span className="text-[10px]" style={{ color: "#55556a" }}>
                    {new Date(thread.inserted_at).toLocaleDateString()}
                  </span>
                </button>
              ))
            )}
          </div>

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

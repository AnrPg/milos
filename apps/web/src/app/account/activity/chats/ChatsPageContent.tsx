"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";

import {
  fetchThreadMessages,
  fetchThreads,
  markThreadRead,
  type ChatMessage,
  type ChatThread,
  type ThreadContextType,
} from "@/api/messaging";
import { MessageBubble } from "@/components/chat/MessageBubble";
import { useSession } from "@/components/session-provider";
import { useUiPrefs } from "@/stores/ui-prefs";
import { useQueryClient } from "@tanstack/react-query";

type Tab = "direct" | "assignment" | "class_slot";

const ROLE_TABS: Record<string, Tab[]> = {
  admin: ["direct", "assignment", "class_slot"],
  coach: ["direct", "assignment", "class_slot"],
  athlete: ["direct", "assignment"],
  member: ["direct", "class_slot"],
};

export function ChatsPageContent() {
  const TAB_SOURCE_BADGE: Record<Tab, string> = {
    direct: i18n("directbc81524"),
    assignment: i18n("workout39463a5"),
    class_slot: i18n("class41ff354"),
  };

  const TAB_LABELS: Record<Tab, string> = {
    direct: i18n("directChat3892e2c"),
    assignment: i18n("workout39463a5"),
    class_slot: i18n("class41ff354"),
  };

  const i18n = useUiTranslations();
  const searchParams = useSearchParams();
  const { tokens, currentUser } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const role = (currentUser as { role?: string } | null)?.role ?? "member";
  const currentUserId = currentUser?.id ?? null;
  const initialThreadId = searchParams.get("thread");

  const { isThreadHidden } = useUiPrefs();
  const queryClient = useQueryClient();

  const availableTabs: Tab[] = useMemo(() => ROLE_TABS[role] ?? ["direct"], [role]);
  const [activeTab, setActiveTab] = useState<Tab>(availableTabs[0]!);
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [selectedThread, setSelectedThread] = useState<ChatThread | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loadingThreads, setLoadingThreads] = useState(true);
  const [loadingMessages, setLoadingMessages] = useState(false);
  const [searchedTabs, setSearchedTabs] = useState<Tab[]>([]);

  useEffect(() => {
    queueMicrotask(() => setSearchedTabs([]));
  }, [initialThreadId]);

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
            setSearchedTabs((current) =>
              current.includes(activeTab) ? current : [...current, activeTab],
            );
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

  const openThread = useCallback(async (thread: ChatThread) => {
    if (!accessToken) return;
    setSelectedThread(thread);
    setLoadingMessages(true);
    try {
      const data = await fetchThreadMessages(accessToken, thread.id);
      setMessages(data.messages);
      const lastMsg = data.messages.at(-1);
      if (lastMsg) {
        void markThreadRead(accessToken, thread.id, lastMsg.id).then(() =>
          queryClient.invalidateQueries({ queryKey: ["messages", "unread"] }),
        );
      }
    } finally {
      setLoadingMessages(false);
    }
  }, [accessToken, queryClient]);

  function threadDisplayName(thread: ChatThread): string {
    if (thread.context_type === "direct") {
      const other = thread.participants.find((p) => p.user_id !== currentUserId);
      return other?.nickname ?? i18n("directMessagefc7f864");
    }
    if (thread.context_type === "assignment") return i18n("workoutThreada03f1e1");
    if (thread.context_type === "class_slot") return i18n("classThreadf030236");
    return i18n("thread7863f75");
  }

  function participantNicknameMap(thread: ChatThread): Record<string, string> {
    const map: Record<string, string> = {};
    thread.participants.forEach((p) => {
      if (p.nickname) map[p.user_id] = p.nickname;
    });
    return map;
  }

  useEffect(() => {
    if (!initialThreadId || loadingThreads || selectedThread?.id === initialThreadId) return;

    const target = threads.find((thread) => thread.id === initialThreadId);
    if (target) {
      queueMicrotask(() => void openThread(target));
      return;
    }

    const nextTab = availableTabs.find((tab) => !searchedTabs.includes(tab));
    if (nextTab && nextTab !== activeTab) {
      queueMicrotask(() => setActiveTab(nextTab));
    }
  }, [
    activeTab,
    availableTabs,
    initialThreadId,
    loadingThreads,
    openThread,
    searchedTabs,
    selectedThread?.id,
    threads,
  ]);

  return (
    <div className="flex flex-col h-full min-h-screen" style={{ background: "var(--bg)" }}>
      <div className="max-w-4xl mx-auto w-full px-4 py-8 flex flex-col gap-6">
        <h1 className="text-xl font-semibold" style={{ color: "var(--text)" }}>
          {i18n("conversationHistory0f18fb3")}
        </h1>

        <div
          className="flex rounded-full p-0.5 gap-0.5"
          style={{ background: "var(--border)", width: "fit-content" }}
        >
          {availableTabs.map((tab) => (
            <button
              key={tab}
              type="button"
              onClick={() => setActiveTab(tab)}
              className="rounded-full px-4 py-1.5 text-sm font-semibold"
              style={
                activeTab === tab
                  ? { background: "var(--text)", color: "var(--bg)" }
                  : { color: "var(--dim)" }
              }
            >
              {TAB_LABELS[tab]}
            </button>
          ))}
        </div>

        <div className="flex gap-4" style={{ minHeight: "480px" }}>
          <div
            className="flex flex-col rounded-[1.5rem] overflow-hidden flex-shrink-0"
            style={{ width: "220px", background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            {loadingThreads ? (
              <p className="text-sm p-4" style={{ color: "var(--dim)" }}>
                {i18n("loading33ce417")}
              </p>
            ) : threads.filter((t) => !isThreadHidden(currentUserId ?? "", t.id)).length === 0 ? (
              <p className="text-sm p-4" style={{ color: "var(--dim)" }}>
                {i18n("noConversations06b83a9")}
              </p>
            ) : (
              threads.filter((t) => !isThreadHidden(currentUserId ?? "", t.id)).map((thread) => (
                <button
                  key={thread.id}
                  type="button"
                  onClick={() => void openThread(thread)}
                  className="flex flex-col gap-1 px-4 py-3 text-left border-b transition-colors hover:bg-[var(--border)]"
                  style={{
                    borderColor: "var(--border)",
                    background: selectedThread?.id === thread.id ? "var(--border)" : "transparent",
                  }}
                >
                  <div className="flex items-center gap-1.5">
                    <span
                      className="rounded-full px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-[0.14em]"
                      style={{
                        background: thread.context_type === "direct"
                          ? "color-mix(in srgb, var(--primary) 15%, transparent)"
                          : thread.context_type === "assignment"
                            ? "color-mix(in srgb, var(--warning) 15%, transparent)"
                            : "color-mix(in srgb, var(--info) 15%, transparent)",
                        color: thread.context_type === "direct"
                          ? "var(--primary)"
                          : thread.context_type === "assignment"
                            ? "var(--warning)"
                            : "var(--info)",
                      }}
                    >
                      {TAB_SOURCE_BADGE[thread.context_type as Tab] ?? thread.context_type}
                    </span>
                  </div>
                  <span className="text-xs font-medium truncate" style={{ color: "var(--text)" }}>
                    {threadDisplayName(thread)}
                  </span>
                  <span className="text-[10px]" style={{ color: "var(--dim)" }}>
                    {new Date(thread.inserted_at).toLocaleDateString()}
                  </span>
                </button>
              ))
            )}
          </div>

          <div
            className="flex flex-col flex-1 rounded-[1.5rem] overflow-hidden"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            {selectedThread ? (
              <div
                className="flex items-center gap-3 px-4 py-3 border-b"
                style={{ borderColor: "var(--border)", background: "var(--panel)" }}
              >
                <span
                  className="rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-[0.14em]"
                  style={{
                    background: selectedThread.context_type === "direct"
                      ? "color-mix(in srgb, var(--primary) 15%, transparent)"
                      : selectedThread.context_type === "assignment"
                        ? "color-mix(in srgb, var(--warning) 15%, transparent)"
                        : "color-mix(in srgb, var(--info) 15%, transparent)",
                    color: selectedThread.context_type === "direct"
                      ? "var(--primary)"
                      : selectedThread.context_type === "assignment"
                        ? "var(--warning)"
                        : "var(--info)",
                  }}
                >
                  {TAB_SOURCE_BADGE[selectedThread.context_type as Tab] ?? selectedThread.context_type}
                </span>
                <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {threadDisplayName(selectedThread)}
                </span>
              </div>
            ) : null}
            {!selectedThread ? (
              <div className="flex items-center justify-center flex-1">
                <p className="text-sm" style={{ color: "var(--dim)" }}>
                  {i18n("selectAConversationToViewMessagesaf2cf2c")}
                </p>
              </div>
            ) : loadingMessages ? (
              <div className="flex items-center justify-center flex-1">
                <p className="text-sm" style={{ color: "var(--dim)" }}>
                  {i18n("loading33ce417")}
                </p>
              </div>
            ) : (
              <div className="flex flex-col gap-2 flex-1 overflow-y-auto p-4">
                {(() => {
                  const nicknames = selectedThread ? participantNicknameMap(selectedThread) : {};
                  return messages.map((msg) => (
                    <MessageBubble
                      key={msg.id}
                      message={msg}
                      isOwnMessage={msg.sender_id === currentUserId}
                      senderNickname={nicknames[msg.sender_id]}
                    />
                  ));
                })()}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

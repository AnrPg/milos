"use client";

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  createDirectThread,
  fetchThreads,
  MESSAGE_TOPICS,
  searchUsers,
  type ChatThread,
  type MessageTopic,
} from "@/api/messaging";
import { fetchCoachingRelationships } from "@/api/roles";
import { PersonName } from "@/components/account/PersonName";
import { PEOPLE_SEARCH_MIN_QUERY, PeopleSearchResults } from "@/components/conversations/PeopleSearchResults";
import { useCoachAudience } from "@/components/journal/EntryAudience";
import { useLanding } from "@/components/member-app/progress/use-landing";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { useChat } from "@/hooks/useChat";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";
import { useUiPrefs } from "@/stores/ui-prefs";

import { MessageBubble } from "../MessageBubble";
import { MessageComposer } from "../MessageComposer";
import { TOPIC_KEYS } from "../message-topics";
import { TypingIndicator } from "../TypingIndicator";
import { showsIn, visibleSegments, threadSegment, threadsIn, type InboxSegment, type ThreadSegmentContext } from "./inbox-model";
import { INBOX_SOURCES, useHasPartners } from "./inbox-sections";
import { BackButton } from "@/components/ui/BackLink";

interface SearchResult {
  id: string;
  nickname: string;
  handle?: string | null;
  role: string;
}

const EMPTY: ReadonlySet<string> = new Set();

/**
 * The one inbox (vision §6.1, ADR-196): «Όλα · Coach · Clubs · Partners»
 * over the gym's threads (direct, workout, class, box) and every other kind
 * of conversation in `INBOX_SOURCES`; a gym thread opens in place. The `/messages`
 * page and the console's drawer both render it; they own the segment and
 * the open thread, so the page keeps them in its address.
 */
export function InboxView({
  segment: requestedSegment,
  onSegmentChange,
  threadId,
  onThreadChange,
  onNavigate,
  heading,
  end,
}: {
  segment: InboxSegment;
  onSegmentChange: (segment: InboxSegment) => void;
  threadId: string | null;
  onThreadChange: (threadId: string | null) => void;
  /** Called when a row leaves the inbox for its own screen. */
  onNavigate?: () => void;
  /** The list's title: the page's `h1`, or the drawer's label. */
  heading: ReactNode;
  /** Shown at the end of the header row, e.g. the drawer's close button. */
  end?: ReactNode;
}) {
  const i18n = useUiTranslations();
  const t = useTranslations("Inbox");
  const { tokens, currentUser } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const currentUserId = currentUser?.id ?? null;

  const { hideThread, isThreadHidden } = useUiPrefs();

  // A segment that is not offered (e.g. «Partners» with none yet) reads as «Όλα».
  const segments = visibleSegments({ hasPartners: useHasPartners() });
  const segment: InboxSegment = segments.includes(requestedSegment) ? requestedSegment : "all";

  const [threads, setThreads] = useState<ChatThread[] | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  // The settled query both searches use: people at my gym and across Palee.
  const [term, setTerm] = useState("");
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [input, setInput] = useState("");
  const [sendError, setSendError] = useState<string | null>(null);
  const [isSending, setIsSending] = useState(false);
  const [asCoaching, setAsCoaching] = useState(false);
  const [topic, setTopic] = useState<MessageTopic | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const { membership } = useSelectedMembershipRole();
  const coaches = can(membership, "manage_coaching");

  // ADR-140 §6: a coaching message goes only to the coach's own clients.
  const clients = useQuery({
    queryKey: ["staff", "coaching-relationships", { coach: currentUserId }],
    enabled: Boolean(accessToken && currentUserId && coaches),
    queryFn: () => fetchCoachingRelationships(accessToken!, { coachUserId: currentUserId! }),
  });
  const clientIds = useMemo(() => new Set((clients.data ?? []).map((item) => item.client_user_id)), [clients.data]);

  // «Coach»: my providers' coaches, my clients, and threads a coaching message came through.
  const audience = useCoachAudience();
  const landing = useLanding();
  const segmentContext: ThreadSegmentContext = useMemo(() => {
    const coachPeerIds = new Set<string>(clientIds);
    for (const provider of audience.data?.providers ?? []) {
      for (const coach of provider.coaches ?? []) coachPeerIds.add(coach.user_id);
    }
    const coachingThreadIds = new Set((landing.data?.coaching_messages ?? []).map((message) => message.thread_id));
    return { currentUserId, coachPeerIds: coachPeerIds.size ? coachPeerIds : EMPTY, coachingThreadIds };
  }, [audience.data, clientIds, currentUserId, landing.data]);

  useEffect(() => {
    if (!accessToken) return;
    // Every gym thread I take part in: direct, workout, class and the box's.
    void fetchThreads(accessToken)
      .then((data) => setThreads(Array.isArray(data.threads) ? data.threads : []))
      .catch(() => setThreads([]));
  }, [accessToken]);

  useEffect(() => {
    const next = searchQuery.trim();
    if (!accessToken || next.length < PEOPLE_SEARCH_MIN_QUERY) {
      queueMicrotask(() => {
        setSearchResults([]);
        setTerm("");
      });
      return;
    }

    const timeout = setTimeout(() => {
      setTerm(next);
      void searchUsers(accessToken, searchQuery)
        .then((data) => {
          const filtered = data.users.filter((u) => u.id !== currentUserId);
          const existingIds = new Set(
            (threads ?? []).flatMap((t) => t.participants.filter((p) => p.user_id !== currentUserId).map((p) => p.user_id)),
          );
          const withThread = filtered.filter((u) => existingIds.has(u.id));
          const withoutThread = filtered.filter((u) => !existingIds.has(u.id));
          setSearchResults([...withThread, ...withoutThread].slice(0, 8));
        })
        .catch(() => setSearchResults([]));
    }, 300);
    return () => clearTimeout(timeout);
  }, [searchQuery, accessToken, currentUserId, threads]);

  const activeThread = threadId ? (threads ?? []).find((thread) => thread.id === threadId) ?? null : null;
  const view: "list" | "thread" = activeThread ? "thread" : "list";

  const { messages, typingUsers, sendMessage, retryMessage, discardMessage, sendTypingStart, sendTypingStop } = useChat({
    threadId: activeThread?.id ?? null,
    accessToken,
    currentUserId,
  });

  useEffect(() => {
    if (view === "thread") messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, view]);

  const openThread = (thread: ChatThread) => {
    setAsCoaching(false);
    setTopic(null);
    setSearchQuery("");
    setSearchResults([]);
    onThreadChange(thread.id);
  };

  const startNewThread = async (targetUser: SearchResult) => {
    if (!accessToken) return;
    const { thread } = await createDirectThread(accessToken, targetUser.id);
    setThreads((prev) => (prev?.some((t) => t.id === thread.id) ? prev : [thread, ...(prev ?? [])]));
    openThread(thread);
  };

  const otherParticipant = (thread: ChatThread) =>
    thread.context_type === "box"
      ? thread.participants.find((p) => p.user_id === thread.context_id)
      : thread.participants.find((p) => p.user_id !== currentUserId);

  // The member's own box thread is «Το box»; staff see the member. Workout
  // and class threads are named by what they are about.
  const threadName = (thread: ChatThread) => {
    if (thread.context_type === "box" && thread.context_id === currentUserId) return i18n("chatsBoxThread");
    if (thread.context_type === "assignment") return t("workoutThread");
    if (thread.context_type === "class_slot") return t("classThread");
    return otherParticipant(thread)?.nickname ?? i18n("directMessagefc7f864");
  };

  const threadKind = (thread: ChatThread) => {
    if (thread.context_type === "box") return i18n("msgKindBox");
    return threadSegment(thread, segmentContext) === "coach" ? t("segment.coach") : null;
  };

  const fromBox = activeThread?.context_type === "box" && activeThread.context_id !== currentUserId;
  const activeOther = activeThread ? otherParticipant(activeThread) : undefined;
  const canCoach = activeThread?.context_type === "direct" && Boolean(activeOther && clientIds.has(activeOther.user_id));

  const handleSend = async () => {
    const draft = input;
    if (!draft.trim() || isSending) return;

    setIsSending(true);
    setSendError(null);

    try {
      await sendMessage(draft, fromBox ? "box_message" : canCoach && asCoaching ? "coaching_message" : "chat", fromBox ? topic : null);
      setInput((current) => (current === draft ? "" : current));
      sendTypingStop();
    } catch (error) {
      setSendError(error instanceof Error ? localizeError(error, i18n) : i18n("messageCouldNotBeSent7aa3b0a"));
    } finally {
      setIsSending(false);
    }
  };

  const visibleThreads = threadsIn(
    (threads ?? []).filter((t) => !isThreadHidden(currentUserId ?? "", t.id)),
    segment,
    segmentContext,
  );
  const sources = INBOX_SOURCES.filter((source) => showsIn(source.segments, segment));
  const topSources = sources.filter((source) => source.placement === "top");
  const bottomSources = sources.filter((source) => source.placement === "bottom");
  const searching = term.length >= PEOPLE_SEARCH_MIN_QUERY;
  const segmentOptions = segments.map((value) => ({ value, label: t(`segment.${value}`) }));

  if (view === "thread" && activeThread) {
    return (
      <div className="flex min-h-0 flex-1 flex-col" data-testid="inbox-thread">
        <div className="flex items-center justify-between gap-3 border-b px-4 py-3" style={{ borderColor: "var(--border)" }}>
          <BackButton onClick={() => onThreadChange(null)} className="min-h-11 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {threadName(activeThread)}
          </BackButton>
          {end}
        </div>
        <div className="scroll-area flex flex-1 flex-col gap-2 overflow-y-auto p-4">
          {messages.map((msg) => (
            <MessageBubble
              key={msg.id}
              message={msg}
              isOwnMessage={msg.sender_id === currentUserId}
              onRetry={retryMessage}
              onDiscard={discardMessage}
            />
          ))}
          <TypingIndicator typingUsers={typingUsers} />
          <div ref={messagesEndRef} />
        </div>

        <div className="border-t p-3" style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}>
          {canCoach ? (
            <label className="mb-2 flex items-start gap-2 text-xs" style={{ color: "var(--text-soft)" }}>
              <input type="checkbox" className="mt-0.5" checked={asCoaching} onChange={(event) => setAsCoaching(event.target.checked)} />
              <span>
                <span className="font-semibold">{i18n("msgSendAsCoaching")}</span>
                <span className="block" style={{ color: "var(--dim)" }}>{i18n("msgSendAsCoachingHint")}</span>
              </span>
            </label>
          ) : null}
          {fromBox ? (
            <div role="radiogroup" aria-label={i18n("msgTopic")} className="mb-2 flex flex-wrap gap-1.5">
              {MESSAGE_TOPICS.map((item) => (
                <button
                  key={item}
                  type="button"
                  role="radio"
                  aria-checked={topic === item}
                  onClick={() => setTopic((current) => (current === item ? null : item))}
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={
                    topic === item
                      ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                      : { background: "var(--card)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }
                  }
                >
                  {i18n(TOPIC_KEYS[item])}
                </button>
              ))}
            </div>
          ) : null}
          <MessageComposer
            error={sendError ? `${sendError} ${i18n("yourDraftIsStillHereReconnectAndRetry617338d")}` : null}
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
          />
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col" data-testid="inbox">
      <div className="flex items-center justify-between gap-3 px-4 pt-3">
        {heading}
        {end}
      </div>
      <div className="flex flex-col gap-2 border-b px-3 py-2" style={{ borderColor: "var(--border)" }}>
        <input
          type="search"
          aria-label={i18n("searchOrStartAConversationabb1d82")}
          placeholder={i18n("searchOrStartAConversationabb1d82")}
          className="w-full rounded-[1rem] px-3 py-2 text-sm outline-none"
          style={{ background: "var(--card)", color: "var(--text)", border: "1px solid var(--border-strong)" }}
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
        />
        {!searching ? (
          <SegmentPicker
            ariaLabel={t("segmentsLabel")}
            options={segmentOptions}
            value={segment}
            onChange={onSegmentChange}
            idPrefix="inbox"
            panelId="inbox-list"
            variant="track"
            stretch
          />
        ) : null}
      </div>

      <div
        id="inbox-list"
        role={!searching ? "tabpanel" : undefined}
        aria-labelledby={!searching ? `inbox-tab-${segment}` : undefined}
        className="group/inbox scroll-area flex-1 overflow-y-auto"
      >
        {searching ? (
          <div className="flex flex-col gap-3 py-2">
            {/* People at my gym start a gym chat (coaching messages need one); anyone else a conversation (ADR-193). */}
            {searchResults.length > 0 ? (
              <section aria-label={t("searchAtGym")}>
                <p className="px-4 pt-1 text-[11px] font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("searchAtGym")}</p>
                {searchResults.map((u) => (
                  <button
                    key={u.id}
                    type="button"
                    onClick={() => void startNewThread(u)}
                    className="flex w-full items-center gap-3 px-4 py-3 text-start transition-colors"
                    style={{ background: "transparent" }}
                  >
                    <Initial letter={u.nickname[0]} />
                    <div className="min-w-0">
                      <PersonName name={u.nickname} handle={u.handle} />
                      <p className="text-xs" style={{ color: "var(--dim)" }}>
                        <SemanticLabel value={u.role} />
                      </p>
                    </div>
                  </button>
                ))}
              </section>
            ) : null}
            <div className="px-3">
              <PeopleSearchResults term={term} excludeIds={new Set(searchResults.map((u) => u.id))} onOpened={onNavigate} />
            </div>
          </div>
        ) : (
          <>
            {topSources.map(({ id, Section }) => (
              <div key={id} data-inbox-source="" className="px-3 pt-3 empty:hidden">
                <Section onNavigate={onNavigate} />
              </div>
            ))}
            {threads === null ? (
              <p className="p-4 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
            ) : (
              visibleThreads.map((thread) => {
                const kind = threadKind(thread);
                return (
                  <div key={thread.id} className="group relative flex items-center border-b" style={{ borderColor: "var(--border)" }}>
                    <button
                      type="button"
                      onClick={() => openThread(thread)}
                      className="flex min-h-14 min-w-0 flex-1 items-center gap-3 px-4 py-3 pe-10 text-start transition-colors"
                    >
                      <Initial letter={threadName(thread)[0]} />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium" style={{ color: "var(--text)" }}>{threadName(thread)}</p>
                        {kind ? <p className="text-xs" style={{ color: "var(--dim)" }}>{kind}</p> : null}
                      </div>
                    </button>
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        hideThread(currentUserId ?? "", thread.id);
                      }}
                      className="absolute end-3 top-1/2 -translate-y-1/2 rounded-lg p-1 text-sm leading-none opacity-0 transition-opacity hover:!opacity-100 group-hover:opacity-60"
                      style={{ color: "var(--dim)" }}
                      title={i18n("hideConversationdfb77ca")}
                      aria-label={i18n("hideConversationdfb77ca")}
                    >
                      🗑️
                    </button>
                  </div>
                );
              })
            )}
            {bottomSources.map(({ id, Section }) => (
              <div key={id} data-inbox-source="" className="px-3 pt-3 empty:hidden">
                <Section onNavigate={onNavigate} />
              </div>
            ))}
            {/* A source renders nothing without rows, so the note hides beside any that has some. */}
            {threads !== null && visibleThreads.length === 0 ? (
              <p className="p-4 text-center text-sm group-has-[[data-inbox-source]>*]/inbox:hidden" style={{ color: "var(--dim)" }}>
                {segment === "all" || segment === "people" ? i18n("noConversationsYetSearchToStartOne1a91cf7") : t("emptySegment")}
              </p>
            ) : null}
          </>
        )}
      </div>
    </div>
  );
}

function Initial({ letter }: { letter: string | undefined }) {
  return (
    <div
      aria-hidden="true"
      className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full text-xs font-bold"
      style={{ background: "color-mix(in srgb, var(--primary) 12%, var(--card))", color: "var(--primary-strong)" }}
    >
      {letter?.toUpperCase() ?? "?"}
    </div>
  );
}

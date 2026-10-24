"use client";

import { useMemo, useState, type ReactNode } from "react";
import Link from "next/link";
import { useInfiniteQuery, useQuery, useQueryClient, type InfiniteData } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchExecution } from "@/api/executions";
import {
  EMPTY_JOURNAL_FILTER,
  fetchJournalPage,
  JOURNAL_FEED_KEY,
  type JournalFeedPage,
  type JournalVisibilityResult,
  type TypedJournalItem,
  type WellnessFeedDay,
} from "@/api/journal";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { ClientPage, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { EntryActions, SourceBadge } from "@/components/client/EntryActions";
import { clientErrorMessage } from "@/components/client/errors";
import { ExecutionPerformanceModal } from "@/components/client/ExecutionPerformanceModal";
import { formatDay, formatTime } from "@/components/client/format";
import { useRepeatWorkout } from "@/components/client/use-repeat-workout";
import { formatElapsed, type HistoryEntry } from "@/components/client/vault";
import { CommentList } from "@/components/journal/CommentList";
import { NoteSheet } from "@/components/journal/NoteSheet";
import { VisibilityBadge } from "@/components/journal/VisibilityBadge";
import { executionHistoryEntry, journalFlow, withAudience, withVisibility } from "@/components/member-app/journal/journal-flow";
import { JournalFilters } from "@/components/member-app/journal/JournalFilters";
import { useRememberedFilter } from "@/components/filters/use-remembered-filter";
import { EntryAudienceNote } from "@/components/journal/EntryAudience";
import { SourceLabel } from "@/components/providers/SourceLabel";
import { useSourceDirectory } from "@/components/providers/use-providers";
import { CHECK_IN_FACES, type CheckInValue } from "@/components/member-app/wellbeing/check-in";
import { BodyFeedCard } from "@/components/body/BodyFeedCard";
import type { DeviceMetrics } from "@/api/devices";
import { DeviceActivityCard, DeviceActivityDetail, DeviceAttachmentLine } from "@/components/devices/DeviceActivityCard";
import { DeviceJournalCard } from "@/components/devices/DeviceJournalCard";
import { FeltLine } from "@/components/wod-goals/FeltLine";
import { ReviewCard } from "@/components/my-reviews";
import { formatScore } from "@/components/pantheon/PantheonCard";
import { InAppShareDialog } from "@/components/share-export/InAppShareDialog";
import { useShareExport } from "@/components/share-export/useShareExport";
import { TrainingLogDialog, TrainingLogEntryCard, type TrainingLogDialogState } from "@/components/training-log/TrainingLog";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { buildExecutionDocument, renderText } from "@/lib/document-export";
import { latestCommentBody, sortComments } from "@/lib/journal-comments";
import { effectiveJournalFilter, journalFilterCount, journalFilterKey, parseJournalFilter } from "@/lib/journal-filter";
import { SeasonTag } from "@/components/seasons/SeasonTag";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const PAGE_SIZE = 30;

/**
 * Ημερολόγιο › Ροή (brief §7.7, ADR-137, ADR-139): every entry the member
 * wrote, from the server's feed, newest first and grouped by day, each with
 * its visibility badge. Finished executions keep performance, repeat and
 * share; logged workouts edit and void; notes edit and delete. New entries
 * start from Νέα καταχώρηση.
 */
export function JournalFlow() {
  const i18n = useUiTranslations();
  const t = useTranslations("MemberApp.journal");
  const tProviders = useTranslations("Providers");
  const tNav = useTranslations("Navigation");
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const directory = useSourceDirectory();
  // Starts from the filter remembered on the account (ADR-151, ADR-162), so
  // it follows the member across devices; a change is remembered with the
  // first page it asks for.
  const { filter, setFilter, changed } = useRememberedFilter("journal", parseJournalFilter, EMPTY_JOURNAL_FILTER, false);
  const queryKey = [...JOURNAL_FEED_KEY, filter ? journalFilterKey(filter) : "pending"] as const;
  const feed = useInfiniteQuery({
    queryKey,
    enabled: Boolean(token) && filter !== null,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => {
      const effective = effectiveJournalFilter(filter!);
      return fetchJournalPage(token!, {
        cursor: pageParam,
        kinds: effective.kinds,
        filter: effective,
        limit: PAGE_SIZE,
        remember: changed && !pageParam,
      });
    },
    getNextPageParam: (last) => last.next_cursor ?? undefined,
  });
  const filtered = filter !== null && journalFilterCount(filter) > 0;
  const { repeat, pendingId, error } = useRepeatWorkout();
  const [performance, setPerformance] = useState<HistoryEntry | null>(null);
  const [sharingId, setSharingId] = useState<string | null>(null);
  const [logDialog, setLogDialog] = useState<TrainingLogDialogState>({ mode: "closed" });
  const [editingNote, setEditingNote] = useState<Extract<TypedJournalItem, { kind: "note" }> | null>(null);
  const [deviceDetail, setDeviceDetail] = useState<{ metrics: DeviceMetrics; title: string } | null>(null);
  const days = useMemo(() => journalFlow(feed.data?.pages ?? []), [feed.data]);

  function refresh() {
    void queryClient.invalidateQueries({ queryKey: JOURNAL_FEED_KEY });
  }

  function moved(result: JournalVisibilityResult) {
    queryClient.setQueryData<InfiniteData<JournalFeedPage>>(queryKey, (data) =>
      data ? { ...data, pages: withVisibility(data.pages, result) } : data,
    );
    refresh();
  }

  // The rung, the source (board 17 Q3) and, on a coach rung, which
  // providers' coaches it reaches (board 17 Q5).
  function badge(item: TypedJournalItem) {
    return (
      <span className="flex flex-wrap items-center gap-2">
        <VisibilityBadge
          item={item}
          onChanged={moved}
          onAudienceChanged={(audience) =>
            queryClient.setQueryData<InfiniteData<JournalFeedPage>>(queryKey, (data) =>
              data ? { ...data, pages: withAudience(data.pages, item, audience) } : data,
            )
          }
        />
        <SourceLabel source={item.source} directory={directory} />
        <EntryAudienceNote item={item} />
      </span>
    );
  }

  return (
    <ClientPage
      title={tNav("journalFlow")}
      intro={i18n("clHistoryIntro")}
    >
      <DeviceJournalCard token={token} locale={locale} />

      {filter ? <JournalFilters filter={filter} onChange={setFilter} /> : null}

      {error ? (
        <ErrorNotice>{clientErrorMessage(error, i18n)}</ErrorNotice>
      ) : null}

      {filter === null || feed.isPending ? (
        <LoadingLine />
      ) : feed.isError ? (
        <QueryProblem error={feed.error} onRetry={() => void feed.refetch()} />
      ) : days.length === 0 ? (
        filtered ? (
          <div className="flex flex-col items-start gap-3">
            <EmptyLine>{tProviders("filter.empty")}</EmptyLine>
            <button
              type="button"
              onClick={() => setFilter(EMPTY_JOURNAL_FILTER)}
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--border)", color: "var(--text)" }}
            >
              {tProviders("filter.clear")}
            </button>
          </div>
        ) : (
          <EmptyLine>{i18n("clHistoryEmpty")}</EmptyLine>
        )
      ) : (
        <ol className="flex flex-col gap-5">
          {days.map((day) => (
            <li key={day.day}>
              <h2 className="mb-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                <time dateTime={day.day}>{formatDay(day.day, locale)}</time>
              </h2>
              <ul className="flex flex-col gap-2">
                {day.items.map((item) => {
                  const key = `${item.kind}:${item.id}`;
                  switch (item.kind) {
                    case "review":
                      return (
                        <li key={key}>
                          <ReviewCard
                            review={item.entry}
                            time={<time dateTime={item.occurred_at}>{formatTime(item.occurred_at, locale)}</time>}
                            badge={badge(item)}
                          />
                        </li>
                      );
                    case "training_log": {
                      const device = item.entry.device;
                      return (
                        <TrainingLogEntryCard
                          key={key}
                          entry={item.entry}
                          locale={locale}
                          badge={badge(item)}
                          device={
                            <>
                              {device ? (
                                <DeviceAttachmentLine device={device} locale={locale} onOpen={() => setDeviceDetail({ metrics: device, title: item.entry.title })} />
                              ) : null}
                              <FeltLine felt={item.entry.felt} />
                            </>
                          }
                          onEdit={() => setLogDialog({ mode: "edit", entry: item.entry })}
                          onVoid={() => setLogDialog({ mode: "void", entry: item.entry })}
                        />
                      );
                    }
                    case "execution": {
                      const entry = executionHistoryEntry(item, day.day);
                      const device = item.entry.device;
                      return (
                        <ExecutionRow
                          key={key}
                          entry={entry}
                          locale={locale}
                          badge={badge(item)}
                          onPerformance={() => setPerformance(entry)}
                          onRepeat={() => void repeat(entry)}
                          onShare={() => setSharingId(entry.id)}
                          repeating={pendingId === entry.id}
                          disabled={Boolean(pendingId)}
                          device={
                            <>
                              {device ? (
                                <DeviceAttachmentLine
                                  device={device}
                                  locale={locale}
                                  onOpen={() => setDeviceDetail({ metrics: device, title: entry.workout_title ?? i18n("workout39463a5") })}
                                />
                              ) : null}
                              <FeltLine felt={item.entry.felt} />
                            </>
                          }
                        />
                      );
                    }
                    case "device_activity":
                      return (
                        <DeviceActivityCard
                          key={key}
                          activity={item.entry}
                          occurredAt={item.occurred_at}
                          locale={locale}
                          badge={badge(item)}
                          onOpen={() => setDeviceDetail({ metrics: item.entry, title: item.entry.title })}
                        />
                      );
                    case "body":
                      return <BodyFeedCard key={key} item={item} locale={locale} badge={badge(item)} />;
                    default:
                      return (
                        <FeedCard key={key} item={item} locale={locale} badge={badge(item)} onEditNote={setEditingNote} />
                      );
                  }
                })}
              </ul>
            </li>
          ))}
        </ol>
      )}

      {feed.hasNextPage ? (
        <button
          type="button"
          onClick={() => void feed.fetchNextPage()}
          disabled={feed.isFetchingNextPage}
          className="min-h-11 rounded-2xl text-sm font-semibold disabled:opacity-50"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {feed.isFetchingNextPage ? t("loadingMore") : t("loadMore")}
        </button>
      ) : null}

      {performance ? (
        <ExecutionPerformanceModal
          executionId={performance.id}
          workoutTitle={performance.workout_title}
          onClose={() => setPerformance(null)}
        />
      ) : null}
      {sharingId && token ? <ShareExecution token={token} executionId={sharingId} onClose={() => setSharingId(null)} /> : null}
      {logDialog.mode !== "closed" && token ? (
        <TrainingLogDialog
          state={logDialog}
          token={token}
          onNavigate={setLogDialog}
          onClose={() => {
            setLogDialog({ mode: "closed" });
            refresh();
          }}
        />
      ) : null}
      {deviceDetail ? (
        <DeviceActivityDetail activity={deviceDetail.metrics} title={deviceDetail.title} locale={locale} onClose={() => setDeviceDetail(null)} />
      ) : null}
      {editingNote ? (
        <NoteSheet
          note={editingNote.entry}
          onClose={() => setEditingNote(null)}
          onSaved={() => {
            setEditingNote(null);
            refresh();
          }}
        />
      ) : null}
    </ClientPage>
  );
}

/** PRs, injuries, notes and check-ins: one card shape, one line of what happened. */
function FeedCard({
  item,
  locale,
  badge,
  onEditNote,
}: {
  item: Exclude<TypedJournalItem, { kind: "execution" | "training_log" | "review" | "body" | "device_activity" }>;
  locale: string;
  badge: ReactNode;
  onEditNote: (item: Extract<TypedJournalItem, { kind: "note" }>) => void;
}) {
  const t = useTranslations("MemberApp.journal");
  const tCheckIn = useTranslations("MemberApp.checkIn");
  const tWellness = useTranslations("MemberApp.wellness");
  const time = item.occurred_on ? null : formatTime(item.occurred_at, locale);
  let title: ReactNode;
  let detail: ReactNode = null;
  let actions: ReactNode = null;

  switch (item.kind) {
    case "pr": {
      const comment = latestCommentBody(item.entry.comments);
      title = (
        <>
          {item.entry.name} · <span className="tabular-nums">{formatScore(Number(item.entry.current_score), item.entry.unit)}</span>{" "}
          {item.entry.unit !== "mins_secs" ? <SemanticLabel value={item.entry.unit} /> : null}
        </>
      );
      detail = comment;
      break;
    }
    case "injury":
      title = (
        <>
          <SemanticLabel value={item.entry.body_area} /> · <SemanticLabel value={item.entry.severity} />
        </>
      );
      detail = item.entry.description;
      break;
    case "note":
      title = t(`noteTopic.${item.entry.topic}`);
      detail = <span className="whitespace-pre-wrap">{item.entry.body}</span>;
      actions = (
        <button
          type="button"
          onClick={() => onEditNote(item)}
          className="rounded-full px-3 py-1.5 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("editNote")}
        </button>
      );
      break;
    case "check_in":
      title = t("kind.check_in");
      detail = item.entry.answers
        .map(
          (answer) =>
            `${CHECK_IN_FACES[answer.value as CheckInValue] ?? ""} ${tCheckIn(`short.${answer.question_key}`)}`,
        )
        .join(" · ");
      break;
    case "wellness":
      title = wellnessDayLine(item.entry, tWellness);
      actions = (
        <Link href="/journal/wellbeing#today" className="rounded-full px-3 py-1.5 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
          {tWellness("open")}
        </Link>
      );
      break;
    case "craving":
      title = tWellness("feed.craving", { intensity: item.entry.intensity });
      detail = [
        ...item.entry.triggers.map((trigger) => tWellness(`trigger.${trigger}`)),
        tWellness(`outcome.${item.entry.outcome ?? "ongoing"}`),
        item.entry.note,
      ]
        .filter(Boolean)
        .join(" · ");
      break;
  }

  return (
    <li className="flex flex-col gap-2 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {t(`kind.${item.kind}`)}
            {time ? <> · <time dateTime={item.occurred_at}>{time}</time></> : null}
          </p>
          <p className="mt-1 break-words text-base font-semibold" style={{ color: "var(--text)" }}>{title}</p>
          {detail ? <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{detail}</p> : null}
          {item.kind === "pr" && (item.entry.comments?.length ?? 0) > 1 ? (
            <div className="mt-2">
              <CommentList comments={sortComments(item.entry.comments ?? [])} />
            </div>
          ) : null}
          <div className="mt-2">{badge}</div>
        </div>
        {actions}
      </div>
    </li>
  );
}

/** «Ευεξία · Τρίτη»: one line for the day, plain counts, no grading words. */
function wellnessDayLine(day: WellnessFeedDay, t: ReturnType<typeof useTranslations>) {
  const kinds = (kind: string) => day.entries.filter((entry) => entry.kind === kind);
  const parts: string[] = [];
  const water = kinds("water");
  if (water.length) parts.push(t("feed.water", { count: water.length }));
  const night = kinds("sleep").find((entry) => !entry.value.nap);
  const minutes = day.summary?.sleep.minutes ?? (night?.value.minutes as number | undefined);
  if (typeof minutes === "number") parts.push(t("sleep.duration", { hours: Math.floor(minutes / 60), minutes: minutes % 60 }));
  const meals = kinds("meal");
  if (meals.length) parts.push(t("feed.meals", { count: meals.length }));
  return parts.join(" · ") || t("feed.empty");
}

function ExecutionRow({
  entry,
  locale,
  badge,
  onPerformance,
  onRepeat,
  onShare,
  repeating,
  disabled,
  device,
}: {
  entry: HistoryEntry;
  locale: string;
  badge: ReactNode;
  device?: ReactNode;
  onPerformance: () => void;
  onRepeat: () => void;
  onShare: () => void;
  repeating: boolean;
  disabled: boolean;
}) {
  const i18n = useUiTranslations();
  const title = entry.workout_title ?? i18n("workout39463a5");
  const elapsed = formatElapsed(entry.total_elapsed_ms);
  return (
    <li
      className="flex flex-col gap-3 rounded-2xl p-4 sm:flex-row sm:items-center sm:justify-between"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="min-w-0">
        <p className="break-words text-base font-semibold" style={{ color: "var(--text)" }}>
          {title}
        </p>
        <SeasonTag season={entry.season} />
        <p className="mt-1 flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--dim)" }}>
          <time dateTime={entry.completed_at_utc}>{formatTime(entry.completed_at_utc, locale)}</time>
          {entry.workout_type ? <SemanticLabel value={entry.workout_type} /> : null}
          {elapsed ? <span className="tabular-nums">{i18n("clElapsedValue", { time: elapsed })}</span> : null}
          {entry.scale_level_slug ? <SemanticLabel value={entry.scale_level_slug} /> : null}
          <SourceBadge source={entry.source} />
        </p>
        {device}
        <div className="mt-2">{badge}</div>
      </div>
      <EntryActions
        workoutTitle={title}
        onPerformance={onPerformance}
        onRepeat={onRepeat}
        onShare={onShare}
        repeating={repeating}
        disabled={disabled}
      />
    </li>
  );
}

/** "Κοινοποίηση στο Palee" of one finished workout, kept from the old landing. */
function ShareExecution({ token, executionId, onClose }: { token: string; executionId: string; onClose: () => void }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const shareExport = useShareExport();
  const execution = useQuery({
    queryKey: ["execution", executionId],
    queryFn: () => fetchExecution(token, executionId),
  });
  if (!execution.data) return null;
  return (
    <InAppShareDialog
      message={renderText(buildExecutionDocument(execution.data, shareExport.labels, locale))}
      onClose={onClose}
      title={execution.data.workout_title ?? i18n("workout39463a5")}
    />
  );
}

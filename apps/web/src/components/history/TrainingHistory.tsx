"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";

import type { TrainingHistoryEntry, TrainingHistoryKind, TrainingHistoryPage } from "@/api/training-history";
import { exerciseText } from "@/lib/training-history";
import { LocalizedScore } from "@/components/localized-score";
import { SourceLabel } from "@/components/providers/SourceLabel";
import { SemanticLabel } from "@/components/semantic-label";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

type Fetcher = (kind: TrainingHistoryKind, offset: number) => Promise<TrainingHistoryPage>;

/**
 * Collapsed-by-default history of workouts (with performance) and booked
 * classes (with the class workout and performance). Pages load as the coach
 * or member scrolls, inside a bounded scroll area, so the profile stays tidy.
 * `footer` sits under the list once open (the member's export, Vault).
 */
export function TrainingHistory({
  id,
  queryKey,
  fetchPage,
  defaultKind,
  title,
  footer,
}: {
  id?: string;
  queryKey: readonly unknown[];
  fetchPage: Fetcher;
  defaultKind: TrainingHistoryKind;
  title?: string;
  footer?: React.ReactNode;
}) {
  const i18n = useUiTranslations();
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState<TrainingHistoryKind>(defaultKind);

  return (
    <section id={id} className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className="flex w-full items-center justify-between gap-4 p-6 text-start"
      >
        <span className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>
          {title ?? i18n("historyTitle")}
        </span>
        <span aria-hidden className="text-xl font-light" style={{ color: "var(--dim)" }}>
          {open ? "−" : "+"}
        </span>
      </button>
      {open ? (
        <div className="border-t px-4 pb-5 pt-4 sm:px-6" style={{ borderColor: "var(--border)" }}>
          <div role="tablist" className="mb-4 inline-flex rounded-full p-1" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            {(["workouts", "classes"] as const).map((option) => (
              <button
                key={option}
                role="tab"
                type="button"
                aria-selected={kind === option}
                onClick={() => setKind(option)}
                className="rounded-full px-4 py-1.5 text-sm font-semibold"
                style={kind === option ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { color: "var(--text-soft)" }}
              >
                {option === "workouts" ? i18n("historyWorkouts") : i18n("historyClasses")}
              </button>
            ))}
          </div>
          <LogList key={kind} kind={kind} queryKey={queryKey} fetchPage={fetchPage} />
          {footer ? <div className="mt-4">{footer}</div> : null}
        </div>
      ) : null}
    </section>
  );
}

function LogList({ kind, queryKey, fetchPage }: { kind: TrainingHistoryKind; queryKey: readonly unknown[]; fetchPage: Fetcher }) {
  const i18n = useUiTranslations();
  const sentinel = useRef<HTMLLIElement | null>(null);
  const scroller = useRef<HTMLOListElement | null>(null);
  const query = useInfiniteQuery({
    queryKey: [...queryKey, "history", kind],
    queryFn: ({ pageParam }) => fetchPage(kind, pageParam),
    initialPageParam: 0,
    getNextPageParam: (last) => last.next_offset ?? undefined,
  });
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = query;

  // Load the next page when the end of the list scrolls into view.
  useEffect(() => {
    const node = sentinel.current;
    if (!node || !hasNextPage) return;
    // Observe within the bounded scroll area, not the page viewport.
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting) && !isFetchingNextPage) void fetchNextPage();
      },
      { root: scroller.current, rootMargin: "120px" },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, [fetchNextPage, hasNextPage, isFetchingNextPage]);

  if (query.isLoading) return <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("historyLoading")}</p>;
  if (query.isError) return <p className="text-sm" style={{ color: "var(--danger)" }}>{i18n("historyError")}</p>;

  const pages = query.data?.pages ?? [];
  const entries = pages.flatMap((page) => page.entries);
  const total = pages[0]?.total ?? 0;

  if (entries.length === 0) {
    return <p className="text-sm" style={{ color: "var(--muted)" }}>{kind === "workouts" ? i18n("historyNoWorkouts") : i18n("historyNoClasses")}</p>;
  }

  return (
    <div>
      <p className="mb-2 text-xs" style={{ color: "var(--muted)" }}>
        {i18n("historyShowing", { shown: entries.length, total })}
      </p>
      <ol ref={scroller} className="max-h-[32rem] space-y-3 overflow-y-auto pe-1" style={{ overscrollBehavior: "contain" }}>
        {entries.map((entry) => (
          <li key={entry.id}>
            <LogEntry entry={entry} kind={kind} />
          </li>
        ))}
        <li ref={sentinel} aria-hidden className="h-1" />
      </ol>
      {hasNextPage ? (
        <button
          type="button"
          disabled={isFetchingNextPage}
          onClick={() => void fetchNextPage()}
          className="mt-3 rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
          style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
        >
          {isFetchingNextPage ? i18n("historyLoading") : i18n("historyShowMore")}
        </button>
      ) : null}
    </div>
  );
}

function LogEntry({ entry, kind }: { entry: TrainingHistoryEntry; kind: TrainingHistoryKind }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const performance = entry.performance;
  const scores = new Map((performance?.scores ?? []).map((score) => [score.section_id, score]));
  const when = entry.occurred_at ? new Date(entry.occurred_at).toLocaleDateString(locale, { weekday: "short", day: "numeric", month: "short", year: "numeric" }) : "—";
  const minutes = performance?.elapsed_ms ? Math.round(performance.elapsed_ms / 60000) : null;

  return (
    <article className="rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <header className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <div className="min-w-0">
          <p className="text-xs" style={{ color: "var(--muted)" }}>
            {when}
            {kind === "classes" && entry.class?.type_name ? ` · ${entry.class.type_name}` : ""}
          </p>
          <h3 className="truncate text-base font-semibold" style={{ color: "var(--text)" }}>
            {kind === "classes" ? entry.class?.name ?? entry.workout?.title : entry.workout?.title ?? i18n("historyDeletedWorkout")}
          </h3>
          {kind === "classes" && entry.workout?.title ? (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{entry.workout.title}</p>
          ) : null}
        </div>
        <div className="flex flex-wrap items-center gap-2 text-xs font-semibold">
          {entry.provider ? <SourceLabel source={entry.provider} /> : null}
          {kind === "classes" && entry.class?.attendance ? <Badge><SemanticLabel value={entry.class.attendance} /></Badge> : null}
          {performance ? <Badge tone="primary"><SemanticLabel value={performance.status} /></Badge> : null}
          {minutes ? <Badge>{i18n("historyMinutes", { minutes })}</Badge> : null}
          {performance?.scale_level_slug ? <Badge>{performance.scale_level_slug}</Badge> : null}
        </div>
      </header>

      {entry.workout?.sections?.length ? (
        <ul className="mt-3 space-y-2">
          {entry.workout.sections.map((section) => {
            const score = scores.get(section.id);
            return (
              <li key={section.id} className={section.nested ? "ms-4" : undefined}>
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {section.name}
                    {section.format !== "untimed" ? (
                      <span className="ms-2 rounded-full px-2 py-0.5 text-[11px] font-bold" style={{ background: "var(--panel)", color: "var(--primary)" }}>
                        <SemanticLabel value={section.format} />
                      </span>
                    ) : null}
                  </p>
                  {score ? (
                    <span className="text-sm font-bold" style={{ color: "var(--primary)" }}>
                      <LocalizedScore value={score.value} scoreType={score.score_type} unit={score.unit} />
                    </span>
                  ) : null}
                </div>
                {section.exercises?.length ? (
                  <p className="text-xs leading-5" style={{ color: "var(--muted)" }}>
                    {section.exercises.map((exercise) => exerciseText(exercise)).join(" · ")}
                  </p>
                ) : null}
              </li>
            );
          })}
        </ul>
      ) : null}

      {!performance ? (
        <p className="mt-3 text-xs italic" style={{ color: "var(--muted)" }}>{i18n("historyNoResult")}</p>
      ) : null}
    </article>
  );
}

function Badge({ children, tone }: { children: React.ReactNode; tone?: "primary" }) {
  return (
    <span className="rounded-full px-2.5 py-1" style={{ background: tone === "primary" ? "color-mix(in srgb, var(--primary) 16%, transparent)" : "var(--panel)", color: tone === "primary" ? "var(--primary)" : "var(--text-soft)" }}>
      {children}
    </span>
  );
}

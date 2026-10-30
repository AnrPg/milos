"use client";

import { useTranslations } from "next-intl";
import React, { type CSSProperties, useMemo } from "react";

import type { ClassTimerPayload } from "@/api/class-timers";
import { usePlanText } from "@/components/workouts/plan-editor/plan-text";
import { formatClock } from "@/components/workouts/execution/TimerDisplay";
import type { ClassTimerPosition } from "@/lib/class-timer";
import { summary } from "@/lib/structured-plan/describe";
import type { ShowWords } from "@/lib/structured-plan/parse";
import { timerNow, type NowBlock, type NowLine, type TimerNow } from "@/lib/timer-now";

/** What is done now at the class timer's position; recomputed only when the segment or window changes. */
export function useTimerNow(payload: ClassTimerPayload | null, position: ClassTimerPosition | null): TimerNow | null {
  const t = useTranslations("PlanRun");
  const words = useMemo<ShowWords>(
    () => ({ perSide: t("show.perSide"), within: t("show.within"), from: t("show.from"), zone: t("show.zone") }),
    [t],
  );
  const segment = position?.segment ?? null;
  const windowIndex = position?.clock?.window?.index ?? null;
  const windowCount = position?.clock?.window?.count ?? null;
  return useMemo(
    () => (payload ? timerNow(payload, { segment, clock: windowIndex === null ? null : ({ window: { index: windowIndex, count: windowCount } } as ClassTimerPosition["clock"]) }, words) : null),
    [payload, segment, windowIndex, windowCount, words],
  );
}

type Size = "wall" | "panel";

/** Wall type shrinks as the list grows, so a whole section still fits the screen. */
function wallFont(now: TimerNow): string {
  const rows = now.blocks.reduce((sum, block) => sum + block.lines.length + (block.text?.split("\n").length ?? 0) + 1, 0);
  if (rows <= 3) return "clamp(1.4rem, 6vmin, 5rem)";
  if (rows <= 6) return "clamp(1.15rem, 4.4vmin, 3.6rem)";
  if (rows <= 10) return "clamp(1rem, 3.4vmin, 2.75rem)";
  return "clamp(0.85rem, 2.5vmin, 2rem)";
}

/**
 * «Τώρα»: the exercises of this minute / interval / round, else the section
 * or the whole WOD, under the class clock (box TV, wall display, coach remote).
 */
export function TimerNowPanel({ now, size, style }: { now: TimerNow | null; size: Size; style?: CSSProperties }) {
  const t = useTranslations("TimerNow");
  if (!now) return null;
  const wall = size === "wall";
  const eyebrow = now.upcoming
    ? t("upNext")
    : { step: t("now"), round: t("eachRound"), section: t("section"), workout: t("workout") }[now.scope];

  return (
    <section
      aria-label={eyebrow}
      data-testid="timer-now"
      data-scope={now.scope}
      data-upcoming={now.upcoming ? "true" : undefined}
      className={`grid content-start overflow-hidden ${wall ? "gap-[1.6vmin]" : "gap-2"}`}
      style={{ fontSize: wall ? wallFont(now) : "1rem", ...style }}
    >
      <p
        className="font-bold uppercase tracking-widest"
        style={{ color: now.upcoming ? "var(--muted)" : "var(--primary)", fontSize: wall ? "0.55em" : "0.75rem" }}
      >
        {eyebrow}
      </p>
      {now.blocks.map((block) => (
        <Block key={block.key} block={block} scope={now.scope} wall={wall} />
      ))}
    </section>
  );
}

function Block({ block, scope, wall }: { block: NowBlock; scope: TimerNow["scope"]; wall: boolean }) {
  const t = useTranslations("TimerNow");
  const words = usePlanText();
  // The clock already names its section; only the whole WOD names each of its sections here.
  const title = scope === "workout" ? block.title : null;
  const params = scope !== "step" && block.plan ? summary(block.plan).params.map(words).join(" · ") : "";
  const heading = block.everySecs ? t("every", { time: formatClock(block.everySecs) }) : [title, params].filter(Boolean).join(" · ");

  return (
    <div className={wall ? "grid gap-[0.8vmin]" : "grid gap-1"}>
      {heading ? (
        <p className="font-semibold" style={{ color: "var(--text-soft)", fontSize: wall ? "0.7em" : "0.875rem" }}>
          {heading}
        </p>
      ) : null}
      {block.text ? (
        <p className="whitespace-pre-wrap font-semibold leading-snug">{block.text}</p>
      ) : (
        <ul className={wall ? "grid gap-[0.6vmin]" : "grid gap-1"}>
          {block.lines.map((line) => (
            <Line key={line.key} line={line} wall={wall} />
          ))}
        </ul>
      )}
    </div>
  );
}

function Line({ line, wall }: { line: NowLine; wall: boolean }) {
  const grouped = line.group !== null;
  return (
    <li
      className="font-semibold leading-tight"
      data-group={line.group?.key}
      style={
        grouped
          ? {
              borderInlineStart: `${wall ? "0.6vmin" : "3px"} solid var(--primary)`,
              paddingInlineStart: wall ? "1.2vmin" : "0.5rem",
              borderStartStartRadius: line.group?.first ? "0.3em" : undefined,
              borderEndStartRadius: line.group?.last ? "0.3em" : undefined,
            }
          : undefined
      }
    >
      {line.dose ? (
        <span className="tabular-nums" style={{ color: "var(--primary)" }}>
          {line.dose}{" "}
        </span>
      ) : null}
      {line.name}
      {line.load ? <span style={{ color: "var(--muted)" }}>{` · ${line.load}`}</span> : null}
    </li>
  );
}

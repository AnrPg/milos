"use client";

import { useTranslations } from "next-intl";
import { type CSSProperties, type FormEvent, type ReactNode, useCallback, useEffect, useRef, useState } from "react";

import { ApiError } from "@/api/client";
import {
  pairBoxScreen,
  type BoxScreenClass,
  type BoxScreenLeaderboard,
  type BoxScreenPairing,
  type BoxScreenToday,
  type BoxScreenWorkout,
} from "@/api/box-screens";
import { ClassTimerFace } from "@/components/class-timer/ClassTimerFace";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { summary } from "@/lib/structured-plan/describe";
import type { PlanSection } from "@/lib/structured-plan/types";
import { usePlanText } from "@/components/workouts/plan-editor/plan-text";
import {
  entryKey,
  formatPairingCode,
  minutesUntil,
  newEntryKeys,
  normalizePairingCode,
  pairingCodeComplete,
  readStoredPairing,
  scaleLabel,
  scoreText,
  screenScene,
  storePairing,
  type ScreenScene,
} from "@/lib/box-screen";
import { formatInZone } from "@/lib/zoned-time";

import { useBoxScreenTimer, useBoxScreenToday, useHydrated } from "./useBoxScreen";

// Mockup s8, option A («Ακολουθεί το τμήμα»): one thing at a time, large
// enough to read from the bar, changing by itself with the class. Every
// colour comes from the theme, so the TV follows light or dark.

const NEW_SCORE_MS = 30_000;

/** palee.app/tv: pairs this TV with a code, then shows the box's day. */
export function BoxScreenTv() {
  // undefined: not chosen on this page yet, so the device's stored pairing (read once hydrated).
  const [chosen, setPairing] = useState<BoxScreenPairing | null | undefined>(undefined);
  const [lostPairing, setLostPairing] = useState(false);
  const hydrated = useHydrated();
  const pairing = chosen !== undefined ? chosen : hydrated ? readStoredPairing() : undefined;
  useScreenWakeLock(Boolean(pairing));

  const unpair = useCallback(() => {
    storePairing(null);
    setLostPairing(true);
    setPairing(null);
  }, []);

  if (pairing === undefined) return <div className="h-dvh" style={{ background: "var(--bg)" }} />;
  if (!pairing) {
    return (
      <PairingView
        lost={lostPairing}
        onPaired={(next) => {
          storePairing(next);
          setLostPairing(false);
          setPairing(next);
        }}
      />
    );
  }
  return <ScreenView key={pairing.screen.id} pairing={pairing} onUnpaired={unpair} />;
}

const tv = {
  eyebrow: { fontSize: "clamp(0.8rem, 1.3vw, 1.6rem)", letterSpacing: "0.2em", color: "var(--muted)" } satisfies CSSProperties,
  line: { fontSize: "clamp(1rem, 2.1vw, 2.6rem)", lineHeight: 1.35 } satisfies CSSProperties,
  small: { fontSize: "clamp(0.85rem, 1.6vw, 2rem)", color: "var(--muted)" } satisfies CSSProperties,
  panel: { background: "var(--panel)", border: "1px solid var(--border)", borderRadius: "1.2vw" } satisfies CSSProperties,
};

function PairingView({ lost, onPaired }: { lost: boolean; onPaired: (pairing: BoxScreenPairing) => void }) {
  const t = useTranslations("BoxScreens");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const host = useHydrated() ? window.location.host : "palee.app";

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!pairingCodeComplete(code) || busy) return;
    setBusy(true);
    setError(null);
    try {
      onPaired(await pairBoxScreen(normalizePairingCode(code)));
    } catch (failure) {
      setError(
        failure instanceof ApiError && failure.status === 422
          ? t("tvCodeInvalid")
          : failure instanceof ApiError && failure.status === 429
            ? t("tvTooMany")
            : t("tvOffline"),
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="grid h-dvh place-items-center p-[3vw] text-center" style={{ background: "var(--bg)", color: "var(--text)" }}>
      <form onSubmit={submit} className="grid w-full max-w-[60rem] justify-items-center gap-[2.4vh]" data-testid="tv-pairing">
        <p className="font-bold uppercase" style={tv.eyebrow}>{t("tvEyebrow")}</p>
        <h1 className="font-extrabold" style={{ fontSize: "clamp(1.6rem, 3vw, 3.6rem)" }}>{t("tvPairTitle")}</h1>
        {lost ? <p style={tv.small} data-testid="tv-lost">{t("tvLost")}</p> : null}
        <label className="grid w-full justify-items-center gap-2">
          <span className="sr-only">{t("codeLabel")}</span>
          <input
            value={formatPairingCode(code)}
            onChange={(event) => {
              setCode(event.target.value);
              setError(null);
            }}
            autoFocus
            autoComplete="off"
            autoCapitalize="characters"
            spellCheck={false}
            inputMode="text"
            placeholder={t("codePlaceholder")}
            aria-invalid={error ? true : undefined}
            aria-describedby={error ? "tv-code-error" : undefined}
            data-testid="tv-code"
            className="w-full max-w-[46rem] rounded-2xl px-4 py-3 text-center font-mono font-extrabold uppercase"
            style={{
              fontSize: "clamp(1.6rem, 5.5vw, 6.5rem)",
              letterSpacing: "0.14em",
              color: "var(--text)",
              background: "var(--panel)",
              border: error ? "2px solid var(--danger)" : "2px solid var(--border)",
            }}
          />
          {error ? (
            <ErrorNotice id="tv-code-error" variant="text" style={{ fontSize: "clamp(0.85rem, 1.6vw, 2rem)", lineHeight: 1.3 }}>
              {error}
            </ErrorNotice>
          ) : null}
        </label>
        <button
          type="submit"
          disabled={!pairingCodeComplete(code) || busy}
          data-testid="tv-pair"
          className="min-h-14 rounded-full px-10 font-bold disabled:opacity-50"
          style={{ fontSize: "clamp(1rem, 2vw, 2.4rem)", background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {busy ? t("tvPairing") : t("tvPair")}
        </button>
        <p style={{ ...tv.small, color: "var(--text-soft)" }}>{t("tvPairHint")}</p>
        <p className="font-mono" style={tv.small}>{`${host}/tv`}</p>
      </form>
    </main>
  );
}

function ScreenView({ pairing, onUnpaired }: { pairing: BoxScreenPairing; onUnpaired: () => void }) {
  const t = useTranslations("BoxScreens");
  const { today, token, now } = useBoxScreenToday(pairing, onUnpaired);

  if (!today) {
    return (
      <main className="grid h-dvh place-items-center" style={{ background: "var(--bg)", color: "var(--muted)" }}>
        <p style={tv.line}>{t("tvLoading")}</p>
      </main>
    );
  }

  return <ScreenDay today={today} token={token} now={now} />;
}

/** One day on the wall, at `now` (exported for tests). */
export function ScreenDay({ today, token, now }: { today: BoxScreenToday; token: string; now: number }) {
  const scene = screenScene(today, now);
  const timerSlot = scene.kind === "timer" ? scene.slot.id : null;
  const timer = useBoxScreenTimer(token, timerSlot);
  const fresh = useNewScores(today);

  return (
    <main className="flex h-dvh flex-col overflow-hidden" style={{ background: "var(--bg)", color: "var(--text)" }} data-testid="tv-screen" data-scene={scene.kind}>
      <Bar today={today} scene={scene} now={now} />
      <SceneBody today={today} scene={scene} now={now} fresh={fresh} timer={timer} />
    </main>
  );
}

/** Rows that just came in stay marked «ΝΕΟ» for 30 seconds. */
function useNewScores(today: BoxScreenToday) {
  const previous = useRef<Map<string, BoxScreenLeaderboard["entries"]>>(new Map());
  const [fresh, setFresh] = useState<Set<string>>(new Set());

  useEffect(() => {
    const added: string[] = [];
    today.leaderboards.forEach((board) => {
      added.push(...newEntryKeys(previous.current.get(board.workout_id) ?? null, board.entries));
      previous.current.set(board.workout_id, board.entries);
    });
    if (added.length === 0) return;
    setFresh((current) => new Set([...current, ...added]));
    const timeout = window.setTimeout(
      () => setFresh((current) => new Set([...current].filter((key) => !added.includes(key)))),
      NEW_SCORE_MS,
    );
    return () => window.clearTimeout(timeout);
  }, [today]);

  return fresh;
}

function useClassLabel(today: BoxScreenToday) {
  const locale = useUiLocale();
  return (slot: BoxScreenClass) => ({
    time: formatInZone(slot.scheduled_at, today.time_zone, locale, "time"),
    name: slot.name ?? slot.class_type ?? "",
  });
}

function Bar({ today, scene, now }: { today: BoxScreenToday; scene: ScreenScene; now: number }) {
  const t = useTranslations("BoxScreens");
  const locale = useUiLocale();
  const label = useClassLabel(today);

  let sub: ReactNode = null;
  if (scene.kind === "preview") {
    const minutes = minutesUntil(scene.slot.scheduled_at, now);
    sub = minutes <= 60 ? t("tvStartsIn", { minutes, ...label(scene.slot) }) : t("tvNext", label(scene.slot));
  } else if (scene.kind === "timer") {
    sub = [t("tvClass", label(scene.slot)), scene.workout?.title].filter(Boolean).join(" · ");
  } else if (scene.kind === "results") {
    sub = scene.slot ? t("tvResults", label(scene.slot)) : t("tvResultsDay");
  } else if (scene.kind !== "idle") {
    const view = { wod: t("tvViewWod"), leaderboard: t("tvViewLeaderboard"), bookings: t("tvViewBookings") }[scene.kind];
    sub = scene.slot ? `${t("tvClass", label(scene.slot))} · ${view}` : view;
  }

  return (
    <header
      className="flex items-center gap-[1.4vw] px-[2vw] py-[1.2vw] font-extrabold"
      style={{ borderBottom: "1px solid var(--border)", fontSize: "clamp(1rem, 1.6vw, 2rem)", letterSpacing: "0.06em" }}
    >
      <span className="truncate uppercase">{today.box.name}</span>
      {sub ? (
        <span className="min-w-0 truncate font-semibold" style={{ color: "var(--muted)", letterSpacing: 0 }} data-testid="tv-bar-sub">
          {sub}
        </span>
      ) : null}
      <span className="ml-auto font-mono tabular-nums" style={{ fontSize: "clamp(1.2rem, 2.2vw, 2.8rem)" }} data-testid="tv-clock">
        {formatInZone(now, today.time_zone, locale, "time")}
      </span>
    </header>
  );
}

function SceneBody({
  today,
  scene,
  now,
  fresh,
  timer,
}: {
  today: BoxScreenToday;
  scene: ScreenScene;
  now: number;
  fresh: Set<string>;
  timer: ReturnType<typeof useBoxScreenTimer>;
}) {
  const t = useTranslations("BoxScreens");
  const grid = "grid min-h-0 flex-1 gap-[1.6vw] px-[2vw] py-[1.8vw]";

  switch (scene.kind) {
    case "preview":
      return (
        <div className={`${grid} grid-cols-1 landscape:grid-cols-[3fr_2fr]`}>
          {scene.workout ? <WodPanel workout={scene.workout} big /> : null}
          <BookingsPanel today={today} slot={scene.slot} />
        </div>
      );
    case "timer": {
      const finished = scene.leaderboard?.entries ?? [];
      return (
        <div className={`${grid} grid-rows-[1fr_auto]`}>
          <div className="grid min-h-0 place-items-center" data-testid="tv-timer">
            {timer.payload ? <ClassTimerFace payload={timer.payload} position={timer.position} size="wall" /> : <ClassClock slot={scene.slot} now={now} />}
          </div>
          {finished.length > 0 ? (
            <section className="flex flex-wrap items-center gap-[1vw] p-[1.4vw]" style={tv.panel} data-testid="tv-finished">
              <h2 className="font-bold uppercase" style={tv.eyebrow}>{t("tvFinished")}</h2>
              <div className="flex flex-wrap gap-[0.7vw]">
                {finished.map((entry) => (
                  <Chip key={entryKey(entry)} spark={fresh.has(entryKey(entry))}>
                    {`${entry.name} ${scoreText(entry)}`.trim()}
                  </Chip>
                ))}
              </div>
            </section>
          ) : null}
        </div>
      );
    }
    case "results":
      return (
        <div className={`${grid} grid-cols-1 landscape:grid-cols-[2fr_1fr]`}>
          <LeaderboardPanel workout={scene.workout} board={scene.leaderboard} fresh={fresh} />
          <section className="grid content-start gap-[0.8vw] p-[1.6vw]" style={tv.panel}>
            <p className="font-semibold" style={tv.small}>{t("tvScoreHint")}</p>
          </section>
        </div>
      );
    case "wod":
      return (
        <div className={grid}>
          <WodPanel workout={scene.workout} big />
        </div>
      );
    case "leaderboard":
      return (
        <div className={grid}>
          <LeaderboardPanel workout={scene.workout} board={scene.leaderboard} fresh={fresh} />
        </div>
      );
    case "bookings":
      return (
        <div className={grid}>
          <BookingsPanel today={today} slot={scene.slot} />
        </div>
      );
    default:
      return (
        <div className="grid flex-1 place-items-center p-[3vw] text-center" data-testid="tv-idle">
          <p className="font-extrabold" style={{ fontSize: "clamp(1.6rem, 3.2vw, 4rem)" }}>
            {today.classes.some((slot) => !slot.cancelled) ? t("tvDayDone") : t("tvNoClasses")}
          </p>
        </div>
      );
  }
}

/** Without a class timer: how long the class has run. */
function ClassClock({ slot, now }: { slot: BoxScreenClass; now: number }) {
  const elapsed = Math.max(0, Math.floor((now - Date.parse(slot.scheduled_at)) / 1000));
  const text = `${String(Math.floor(elapsed / 60)).padStart(2, "0")}:${String(elapsed % 60).padStart(2, "0")}`;
  return (
    <div role="timer" className="font-mono font-bold tabular-nums leading-none" style={{ fontSize: "min(16vw, 40vh)" }}>
      {text}
    </div>
  );
}

function Chip({ children, spark = false }: { children: ReactNode; spark?: boolean }) {
  return (
    <span
      className="rounded-full px-[1.1vw] py-[0.4vw] font-bold"
      data-new={spark ? "true" : undefined}
      style={{
        fontSize: "clamp(0.9rem, 1.6vw, 2rem)",
        background: spark ? "var(--spark)" : "var(--panel-muted)",
        color: spark ? "var(--spark-contrast)" : "var(--text)",
      }}
    >
      {children}
    </span>
  );
}

function WodPanel({ workout, big = false }: { workout: BoxScreenWorkout; big?: boolean }) {
  const t = useTranslations("BoxScreens");
  return (
    <section className="grid min-h-0 content-start gap-[0.8vw] overflow-hidden p-[1.6vw]" style={tv.panel} data-testid="tv-wod">
      <h2 className="font-bold uppercase" style={tv.eyebrow}>{t("tvWodTitle")}</h2>
      {workout.title ? (
        <h3 className="font-black leading-none" style={{ fontSize: big ? "clamp(2rem, 5vw, 6rem)" : "clamp(1.6rem, 3.2vw, 4rem)" }}>
          {workout.title}
        </h3>
      ) : null}
      <WorkoutLines body={workout.body} />
    </section>
  );
}

type ExerciseLine = { id?: string; name?: string; prescription_value?: string | number | null; prescription_unit?: string | null; load_value?: string | null; item_type?: string; excluded?: boolean };

function WorkoutLines({ body }: { body: BoxScreenWorkout["body"] }) {
  if (body.kind === "free_text") {
    return body.text ? <p className="whitespace-pre-wrap font-bold" style={tv.line}>{body.text}</p> : null;
  }
  if (body.kind === "text_sections") {
    return (
      <>
        {body.sections.map((section, index) => (
          <div key={section.id ?? index} className="font-bold" style={tv.line}>
            {section.title ? <div style={{ color: "var(--text-soft)" }}>{section.title}</div> : null}
            <p className="whitespace-pre-wrap">{section.text}</p>
          </div>
        ))}
      </>
    );
  }
  return (
    <>
      {body.sections.map((section, index) =>
        "plan" in section ? (
          <PlanSectionLines key={section.id ?? index} name={section.name} plan={section.plan as PlanSection | null} />
        ) : (
        <div key={section.id ?? index} className="font-bold" style={tv.line}>
          <div style={{ color: "var(--text-soft)" }}>{[section.name, section.subtitle].filter(Boolean).join(" · ")}</div>
          {(section.exercises as ExerciseLine[])
            .filter((exercise) => !exercise.excluded && exercise.item_type !== "header")
            .map((exercise, row) => (
              <div key={exercise.id ?? row}>
                {[exercise.prescription_value, exercise.prescription_unit && exercise.prescription_unit !== "reps" ? exercise.prescription_unit : null, exercise.name]
                  .filter((part) => part !== null && part !== undefined && part !== "")
                  .join(" ")}
                {exercise.load_value ? <span style={{ color: "var(--muted)" }}>{` · ${exercise.load_value}`}</span> : null}
              </div>
            ))}
        </div>
        ),
      )}
    </>
  );
}

/** ADR-270: a structured section as its one-line summary, then its exercises per block. */
function PlanSectionLines({ name, plan }: { name: string; plan: PlanSection | null }) {
  const words = usePlanText();
  const t = useTranslations("PlanEditor");
  if (!plan) return null;
  const sum = summary(plan);
  const params = sum.params.map(words).join(" · ");
  return (
    <div className="font-bold" style={tv.line}>
      <div style={{ color: "var(--text-soft)" }}>{[name, params].filter(Boolean).join(" · ")}</div>
      {sum.names.map((block, row) => (
        <div key={row}>{block.map((n) => (n.perSide ? `${n.name} (${t("perSide")})` : n.name)).join(" + ")}</div>
      ))}
    </div>
  );
}

function BookingsPanel({ today, slot }: { today: BoxScreenToday; slot: BoxScreenClass }) {
  const t = useTranslations("BoxScreens");
  const label = useClassLabel(today)(slot);
  const { names, unnamed, count, capacity } = slot.bookings;
  const free = Math.max(0, capacity - count);
  return (
    <section className="grid min-h-0 content-start gap-[0.8vw] overflow-hidden p-[1.6vw]" style={tv.panel} data-testid="tv-bookings">
      <h2 className="font-bold uppercase" style={tv.eyebrow}>{t("tvBookingsTitle", { ...label, count, capacity })}</h2>
      <div className="flex flex-wrap gap-[0.7vw]">
        {names.map((name, index) => (
          <Chip key={`${name}-${index}`}>{name}</Chip>
        ))}
        {unnamed > 0 ? <Chip>{t("tvMore", { count: unnamed })}</Chip> : null}
      </div>
      <p className="font-semibold" style={tv.small}>{free > 0 ? t("tvFreeSpots", { count: free }) : t("tvFull")}</p>
    </section>
  );
}

function LeaderboardPanel({
  workout,
  board,
  fresh,
}: {
  workout: BoxScreenWorkout | null;
  board: BoxScreenLeaderboard | null;
  fresh: Set<string>;
}) {
  const t = useTranslations("BoxScreens");
  const entries = board?.entries ?? [];
  return (
    <section className="grid min-h-0 content-start gap-[0.4vw] overflow-hidden p-[1.6vw]" style={tv.panel} data-testid="tv-leaderboard">
      <h2 className="font-bold uppercase" style={tv.eyebrow}>
        {workout?.title ? t("tvLeaderboardTitle", { title: workout.title }) : t("tvViewLeaderboard")}
      </h2>
      {entries.length === 0 ? (
        <p className="font-semibold" style={tv.small}>{t("tvNoScores")}</p>
      ) : (
        <ol className="grid">
          {entries.map((entry) => {
            const isNew = fresh.has(entryKey(entry));
            const scale = scaleLabel(entry.scale_level_slug);
            return (
              <li
                key={entryKey(entry)}
                data-new={isNew ? "true" : undefined}
                className="grid items-center gap-[1vw] rounded-[0.6vw] px-[0.4vw] py-[0.5vw]"
                style={{
                  gridTemplateColumns: "2.6vw minmax(0, 1fr) auto",
                  fontSize: "clamp(1rem, 1.9vw, 2.4rem)",
                  borderBottom: "1px solid var(--border)",
                  background: isNew ? "color-mix(in srgb, var(--spark) 18%, transparent)" : undefined,
                }}
              >
                <b className="font-mono" style={{ color: "var(--muted)" }}>{entry.rank}</b>
                <span className="truncate font-semibold">
                  {entry.name}
                  {isNew ? (
                    <span className="ml-[0.6vw] rounded-[0.5vw] px-[0.8vw] py-[0.2vw] font-extrabold" style={{ fontSize: "0.7em", background: "var(--spark)", color: "var(--spark-contrast)" }}>
                      {t("tvNew")}
                    </span>
                  ) : null}
                </span>
                <span className="font-mono font-extrabold">
                  {scoreText(entry)}
                  {scale ? (
                    <span className="ml-[0.6vw] rounded-[0.5vw] px-[0.7vw] py-[0.1vw] font-sans font-extrabold" style={{ fontSize: "0.7em", background: "var(--panel-muted)", color: "var(--text-soft)" }}>
                      {scale}
                    </span>
                  ) : null}
                </span>
              </li>
            );
          })}
        </ol>
      )}
    </section>
  );
}

"use client";

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import {
  deleteWellnessEntry,
  fetchWellness,
  logWellnessEntry,
  WELLNESS_KEY,
  type Craving,
  type MealSlot,
  type WellnessDay,
  type WellnessEntry,
  type WellnessItem,
  type WellnessOverview,
} from "@/api/wellness";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

import { WellnessConsentCard, WellnessCustomizeSheet } from "./WellnessSettings";
import { CravingSheet, HowDidItGo, MealSheet, SleepSheet } from "./WellnessForms";
import { wellnessErrorMessage } from "./wellness-errors";
import {
  addDays,
  cravingsOn,
  DAYS_BACK,
  editable,
  entriesOn,
  glasses,
  hoursAndMinutes,
  isMainSlot,
  localDate,
  mealSlots,
  mealsBySlot,
  occurredAt,
  openCraving,
  planFit,
  portionBars,
  usualNight,
  visibleItems,
  weekDots,
  weekOf,
  weekRows,
  type Dot,
} from "./wellness-model";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const [FIT_LOGGED, FIT_EMPTY, FIT_OPTIONAL] = ["logged", "empty", "optional"];
/** The chip state of a meal slot: the plan fit when logged, else whether the slot is expected. */
function slotFit(meal: WellnessEntry | null | undefined, slot: MealSlot | null): string {
  if (meal) return planFit(meal) ?? FIT_LOGGED;
  return slot && isMainSlot(slot) ? FIT_EMPTY : FIT_OPTIONAL;
}

type Sheet =
  | { kind: "sleep" }
  | { kind: "meal"; slot: MealSlot | null; meal: WellnessEntry | null }
  | { kind: "craving"; craving: Craving | null }
  | { kind: "customize" };

/** The window one request covers: the shown week and the last 7 days. */
export function wellnessWindow(today: string, weekOffset: number) {
  const week = weekOf(today, weekOffset);
  const from = [week.from, addDays(today, -DAYS_BACK)].sort()[0];
  const to = [week.to, today].sort()[0];
  return { week, from, to };
}

export function useWellness(from: string, to: string) {
  const { tokens } = useSession();
  return useQuery({
    queryKey: [...WELLNESS_KEY, from, to],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchWellness(tokens!.access_token, from, to),
  });
}

/**
 * Ημερολόγιο › Ευεξία (ADR-159, board 14): «Σήμερα» as large tiles in the
 * member's order (Q1 B), one tap for a glass, sheets for sleep, meals and
 * Λιγούρα, the coach's plan as hand portions with numbers hidden until
 * asked, and the week as a grid of dots. Past days up to a week back can be
 * filled in. No streaks, no scores, nothing compared with anyone.
 */
export function WellnessPanel({ initialCraving }: { initialCraving?: string | null }) {
  const t = useTranslations("MemberApp.wellness");
  const ui = useUiTranslations();
  const format = useFormatter();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const today = localDate(new Date());
  const [day, setDay] = useState(today);
  const [weekOffset, setWeekOffset] = useState(0);
  const [chosen, setChosen] = useState<Sheet | null>(null);
  const [initialSeen, setInitialSeen] = useState(false);
  const [undo, setUndo] = useState<WellnessEntry | null>(null);
  const [showNumbers, setShowNumbers] = useState(false);
  const range = wellnessWindow(today, weekOffset);
  const query = useWellness(range.from, range.to);
  const data = query.data;

  function refresh() {
    void queryClient.invalidateQueries({ queryKey: WELLNESS_KEY });
  }

  const addGlass = useMutation({
    mutationFn: async () => {
      const at = occurredAt(day, new Date());
      return logWellnessEntry(tokens!.access_token, {
        kind: "water",
        value: { ml: data!.preferences.glass_ml },
        ...(at ? { occurred_at: at } : {}),
      });
    },
    onSuccess: (entry) => {
      setUndo(entry);
      refresh();
    },
  });

  const removeEntry = useMutation({
    mutationFn: async (id: string) => deleteWellnessEntry(tokens!.access_token, id),
    onSuccess: () => {
      setUndo(null);
      refresh();
    },
  });

  useEffect(() => {
    if (!undo) return;
    const timer = setTimeout(() => setUndo(null), 6000);
    return () => clearTimeout(timer);
  }, [undo]);

  // A «Πώς πήγε;» notification or Νέα καταχώρηση › Λιγούρα opens the sheet once.
  const initialSheet: Sheet | null = (() => {
    if (initialSeen || !data || !initialCraving) return null;
    if (initialCraving === "new") return { kind: "craving", craving: null };
    const craving = data.cravings.find((entry) => entry.id === initialCraving);
    return craving ? { kind: "craving", craving } : null;
  })();
  const sheet = chosen ?? initialSheet;
  const setSheet = (next: Sheet | null) => {
    setInitialSeen(true);
    setChosen(next);
  };

  if (query.isPending) return <PanelShell title={t("today")}><p style={{ color: "var(--dim)" }}>{t("loading")}</p></PanelShell>;
  if (query.isError || !data)
    return (
      <PanelShell title={t("today")}>
        <ErrorNotice>{wellnessErrorMessage(query.error, (key) => t(key), ui)}</ErrorNotice>
      </PanelShell>
    );

  if (!data.consented) return <WellnessConsentCard preferences={data.preferences} onDone={refresh} />;

  const summary = data.days.find((entry) => entry.date === day);
  const plan = data.plans[0] ?? null;
  const items = visibleItems(data.preferences).filter((item) => item !== "plan" || plan);
  const dayCravings = cravingsOn(data.cravings, day);
  const nights = entriesOn(data.entries, day, "sleep");
  const night = nights.find((entry) => !entry.value.nap) ?? null;
  const meals = entriesOn(data.entries, day, "meal");
  const waters = entriesOn(data.entries, day, "water");
  const dayLabel =
    day === today
      ? t("today")
      : day === addDays(today, -1)
        ? t("yesterday")
        : format.dateTime(new Date(`${day}T12:00:00`), { weekday: "long", day: "numeric", month: "short" });

  const tiles: Record<WellnessItem, ReactNode> = {
    water: summary ? (
      <WaterTile
        day={summary}
        entries={waters}
        pending={addGlass.isPending}
        onAdd={() => addGlass.mutate()}
        onRemove={(id) => removeEntry.mutate(id)}
      />
    ) : null,
    sleep: summary ? <SleepTile day={summary} onOpen={() => setSheet({ kind: "sleep" })} /> : null,
    meals: (
      <MealsTile
        slots={mealSlots(plan)}
        meals={meals}
        hasPlan={Boolean(plan)}
        onOpen={(slot, meal) => setSheet({ kind: "meal", slot, meal })}
      />
    ),
    plan: plan ? (
      <PlanTile
        title={plan.title}
        bars={portionBars(summary?.meals.portions, plan.portions)}
        showNumbers={showNumbers}
        onToggleNumbers={() => setShowNumbers(!showNumbers)}
      />
    ) : null,
    mood: <MoodTile mood={summary?.mood ?? null} />,
  };

  return (
    <div className="flex flex-col gap-4" id="today">
      <PanelShell
        title={dayLabel}
        actions={
          <>
            <DayStepper
              canBack={editable(addDays(day, -1), today)}
              canForward={day < today}
              onBack={() => setDay(addDays(day, -1))}
              onForward={() => setDay(addDays(day, 1))}
            />
            <button
              type="button"
              onClick={() => setSheet({ kind: "customize" })}
              className="min-h-9 rounded-full px-3 text-xs font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("customize")}
            </button>
          </>
        }
      >
        <ul className="grid grid-cols-2 gap-3" data-testid="wellness-tiles">
          {items.map((item) =>
            tiles[item] ? (
              <li key={item} className={item === "meals" || item === "plan" ? "col-span-2" : undefined}>
                {tiles[item]}
              </li>
            ) : null,
          )}
          <li className="col-span-2">
            <CravingTile
              cravings={dayCravings}
              onNew={() => setSheet({ kind: "craving", craving: null })}
              onOpen={(craving) => setSheet({ kind: "craving", craving })}
              onAnswered={refresh}
            />
          </li>
        </ul>
        {undo ? (
          <div
            role="status"
            className="mt-3 flex items-center justify-between gap-3 rounded-2xl px-4 py-2 text-sm"
            style={{ background: "var(--panel-raised)", color: "var(--text)" }}
          >
            {t("water.added", { ml: undo.value.ml as number })}
            <button
              type="button"
              onClick={() => removeEntry.mutate(undo.id)}
              className="font-bold"
              style={{ color: "var(--primary)" }}
            >
              {t("undo")}
            </button>
          </div>
        ) : null}
        {addGlass.error || removeEntry.error ? (
          <ErrorNotice className="mt-3">{wellnessErrorMessage(addGlass.error ?? removeEntry.error, (key) => t(key), ui)}</ErrorNotice>
        ) : null}
      </PanelShell>

      <WeekCard
        data={data}
        week={range.week}
        today={today}
        selected={day}
        onSelect={(date) => editable(date, today) && setDay(date)}
        onShift={(step) => setWeekOffset(Math.min(0, weekOffset + step))}
        canForward={weekOffset < 0}
      />

      {sheet?.kind === "sleep" ? (
        <SleepSheet
          day={day}
          night={night}
          usual={usualNight(data.entries)}
          onClose={() => setSheet(null)}
          onSaved={() => {
            setSheet(null);
            refresh();
          }}
        />
      ) : null}
      {sheet?.kind === "meal" ? (
        <MealSheet
          day={day}
          slot={sheet.slot}
          meal={sheet.meal}
          plan={plan}
          photo={sheet.meal?.value.media_id ? data.photos[String(sheet.meal.value.media_id)] ?? null : null}
          photoTypes={data.photo_capabilities.content_types}
          onClose={() => setSheet(null)}
          onSaved={() => {
            setSheet(null);
            refresh();
          }}
        />
      ) : null}
      {sheet?.kind === "craving" ? (
        <CravingSheet
          craving={sheet.craving}
          onClose={() => setSheet(null)}
          onSaved={() => {
            setSheet(null);
            refresh();
          }}
          onWater={data.preferences.hidden_items.includes("water") ? null : () => addGlass.mutate()}
        />
      ) : null}
      {sheet?.kind === "customize" ? (
        <WellnessCustomizeSheet
          preferences={data.preferences}
          onClose={() => setSheet(null)}
          onSaved={refresh}
        />
      ) : null}
    </div>
  );
}

function PanelShell({ title, actions, children }: { title: string; actions?: ReactNode; children: ReactNode }) {
  const t = useTranslations("MemberApp.wellness");
  return (
    <section
      aria-label={t("eyebrow")}
      className="rounded-3xl p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("eyebrow")}</p>
          <h2 className="text-xl font-extrabold first-letter:uppercase" style={{ color: "var(--text)" }}>{title}</h2>
        </div>
        {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
      </div>
      {children}
    </section>
  );
}

function DayStepper({
  canBack,
  canForward,
  onBack,
  onForward,
}: {
  canBack: boolean;
  canForward: boolean;
  onBack: () => void;
  onForward: () => void;
}) {
  const t = useTranslations("MemberApp.wellness");
  const style = { border: "1px solid var(--border)", color: "var(--text)" };
  return (
    <div className="flex items-center gap-1">
      <button type="button" aria-label={t("previousDay")} disabled={!canBack} onClick={onBack} className="h-9 w-9 rounded-full disabled:opacity-40" style={style}>
        ‹
      </button>
      <button type="button" aria-label={t("nextDay")} disabled={!canForward} onClick={onForward} className="h-9 w-9 rounded-full disabled:opacity-40" style={style}>
        ›
      </button>
    </div>
  );
}

function Tile({
  label,
  value,
  detail,
  color,
  action,
  onOpen,
}: {
  label: string;
  value: ReactNode;
  detail?: ReactNode;
  color: string;
  action?: ReactNode;
  onOpen?: () => void;
}) {
  const body = (
    <>
      <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color }}>{label}</span>
      <span className="text-lg font-extrabold leading-tight" style={{ color: "var(--text)" }}>{value}</span>
      {detail ? <span className="text-xs" style={{ color: "var(--dim)" }}>{detail}</span> : null}
    </>
  );
  return (
    <div
      className="flex h-full min-h-28 flex-col justify-between gap-2 rounded-2xl p-4"
      style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
    >
      {onOpen ? (
        <button type="button" onClick={onOpen} className="flex flex-col items-start gap-1 text-start">
          {body}
        </button>
      ) : (
        <div className="flex flex-col gap-1">{body}</div>
      )}
      {action}
    </div>
  );
}

function WaterTile({
  day,
  entries,
  pending,
  onAdd,
  onRemove,
}: {
  day: WellnessDay;
  entries: WellnessEntry[];
  pending: boolean;
  onAdd: () => void;
  onRemove: (id: string) => void;
}) {
  const t = useTranslations("MemberApp.wellness");
  const { filled, goal } = glasses(day.water);
  const drops = Math.max(goal, entries.length);
  return (
    <Tile
      label={t("item.water")}
      color="var(--info)"
      value={t("water.glasses", { filled, goal })}
      detail={
        <span className="flex flex-wrap gap-1" aria-label={t("water.dropsLabel")}>
          {Array.from({ length: drops }, (_, index) => {
            const entry = entries[index];
            return entry ? (
              <button
                key={entry.id}
                type="button"
                aria-label={t("water.remove")}
                onClick={() => onRemove(entry.id)}
                className="h-3.5 w-3.5 rounded-full"
                style={{ background: "var(--info)" }}
              />
            ) : (
              <span key={`empty-${index}`} className="h-3.5 w-3.5 rounded-full" style={{ border: "1px solid var(--border)" }} />
            );
          })}
        </span>
      }
      action={
        <button
          type="button"
          onClick={onAdd}
          disabled={pending}
          className="min-h-11 rounded-2xl text-base font-extrabold disabled:opacity-60"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("water.add")}
        </button>
      }
    />
  );
}

function SleepTile({ day, onOpen }: { day: WellnessDay; onOpen: () => void }) {
  const t = useTranslations("MemberApp.wellness");
  const sleep = day.sleep;
  const duration = typeof sleep.minutes === "number" ? hoursAndMinutes(sleep.minutes) : null;
  const details = [
    sleep.quality ? t("sleep.qualityValue", { quality: sleep.quality }) : null,
    sleep.source && sleep.source !== "manual" ? t("sleep.fromDevice", { source: t(`source.${sleep.source}`) }) : null,
    sleep.nap_minutes > 0 ? t("sleep.napValue", { minutes: sleep.nap_minutes }) : null,
  ].filter(Boolean);
  return (
    <Tile
      label={t("item.sleep")}
      color="var(--series-4)"
      value={duration ? t("sleep.duration", duration) : t("sleep.empty")}
      detail={details.join(" · ") || t("sleep.tap")}
      onOpen={onOpen}
    />
  );
}

function MealsTile({
  slots,
  meals,
  hasPlan,
  onOpen,
}: {
  slots: MealSlot[];
  meals: WellnessEntry[];
  hasPlan: boolean;
  onOpen: (slot: MealSlot | null, meal: WellnessEntry | null) => void;
}) {
  const t = useTranslations("MemberApp.wellness");
  const { named, other } = mealsBySlot(meals, slots);
  return (
    <div className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
      <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--success)" }}>
        {t("item.meals")}
      </span>
      <ul className="flex flex-wrap gap-2">
        {named.flatMap(({ slot, meals: logged }) =>
          (logged.length ? logged : [null]).map((meal, index) => (
            <li key={`${slot}-${meal?.id ?? index}`}>
              <SlotChip
                label={t(`slot.${slot}`)}
                fit={slotFit(meal, slot)}
                fitLabel={meal ? fitWord(t, meal, hasPlan) : null}
                onClick={() => onOpen(slot, meal)}
              />
            </li>
          )),
        )}
        {other.map((meal) => (
          <li key={meal.id}>
            <SlotChip label={t("meal.title")} fit={slotFit(meal, null)} fitLabel={fitWord(t, meal, hasPlan)} onClick={() => onOpen(null, meal)} />
          </li>
        ))}
        <li>
          <button
            type="button"
            onClick={() => onOpen("snack", null)}
            className="min-h-10 rounded-full px-3 text-sm font-semibold"
            style={{ border: "1px dashed var(--border)", color: "var(--dim)" }}
          >
            {t("meal.addSnack")}
          </button>
        </li>
      </ul>
    </div>
  );
}

function fitWord(t: ReturnType<typeof useTranslations>, meal: WellnessEntry, hasPlan: boolean) {
  const fit = planFit(meal);
  if (!fit) return t("meal.logged");
  return t(`meal.fit.${hasPlan ? "plan" : "own"}.${fit}`);
}

/** Green or amber outline only, never a score (board 14, Q4). */
function SlotChip({
  label,
  fit,
  fitLabel,
  onClick,
}: {
  label: string;
  fit: string;
  fitLabel: string | null;
  onClick: () => void;
}) {
  const border =
    fit === "in_plan"
      ? "var(--success)"
      : fit === "off_plan"
        ? "var(--warning)"
        : fit === "logged"
          ? "var(--primary)"
          : "var(--border)";
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex min-h-10 flex-col items-start justify-center rounded-2xl px-3 py-1 text-start text-sm font-semibold"
      style={{ border: `2px solid ${border}`, color: "var(--text)", borderStyle: fit === "optional" ? "dashed" : "solid" }}
    >
      {label}
      <span className="text-[11px] font-normal" style={{ color: "var(--dim)" }}>{fitLabel ?? "—"}</span>
    </button>
  );
}

function PlanTile({
  title,
  bars,
  showNumbers,
  onToggleNumbers,
}: {
  title: string;
  bars: ReturnType<typeof portionBars>;
  showNumbers: boolean;
  onToggleNumbers: () => void;
}) {
  const t = useTranslations("MemberApp.wellness");
  return (
    <div className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
          {t("plan.title", { title })}
        </span>
        {bars.length ? (
          <button type="button" onClick={onToggleNumbers} className="text-xs font-semibold" style={{ color: "var(--primary)" }}>
            {showNumbers ? t("plan.hideNumbers") : t("plan.showNumbers")}
          </button>
        ) : null}
      </div>
      {bars.length ? (
        <ul className="flex flex-col gap-2">
          {bars.map((bar) => (
            <li key={bar.key} className="flex flex-col gap-1">
              <span className="flex justify-between text-xs" style={{ color: "var(--text)" }}>
                {t(`portion.${bar.key}`)}
                {showNumbers ? <span className="tabular-nums">{t("plan.of", { logged: bar.logged, target: bar.target })}</span> : null}
              </span>
              <span
                className="h-2 overflow-hidden rounded-full"
                role="meter"
                aria-valuemin={0}
                aria-valuemax={bar.target}
                aria-valuenow={bar.logged}
                aria-label={t(`portion.${bar.key}`)}
                style={{ background: "var(--panel-muted)" }}
              >
                <span className="block h-full rounded-full" style={{ width: `${bar.ratio * 100}%`, background: "var(--primary)" }} />
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("plan.noPortions")}</p>
      )}
    </div>
  );
}

function MoodTile({ mood }: { mood: WellnessDay["mood"] | null }) {
  const t = useTranslations("MemberApp.wellness");
  const parts = [
    typeof mood?.mood === "number" ? t("mood.mood", { value: mood.mood }) : null,
    typeof mood?.stress === "number" ? t("mood.stress", { value: mood.stress }) : null,
  ].filter(Boolean);
  return (
    <Tile
      label={t("item.mood")}
      color="var(--warning)"
      value={parts.length ? parts.join(" · ") : t("mood.empty")}
      detail={<a href="#check-in" style={{ color: "var(--primary)" }}>{t("mood.open")}</a>}
    />
  );
}

function CravingTile({
  cravings,
  onNew,
  onOpen,
  onAnswered,
}: {
  cravings: Craving[];
  onNew: () => void;
  onOpen: (craving: Craving) => void;
  onAnswered: () => void;
}) {
  const t = useTranslations("MemberApp.wellness");
  const open = cravings.filter(openCraving);
  return (
    <div className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
      <button type="button" onClick={onNew} className="flex items-center justify-between gap-3 text-start" data-testid="craving-open">
        <span>
          <span className="block text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--series-5)" }}>{t("item.cravings")}</span>
          <span className="block text-base font-extrabold" style={{ color: "var(--text)" }}>{t("craving.tileTitle")}</span>
          <span className="block text-xs" style={{ color: "var(--dim)" }}>
            {cravings.length ? t("craving.count", { count: cravings.length }) : t("craving.tileHint")}
          </span>
        </span>
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
      </button>
      {open.map((craving) => (
        <div key={craving.id} className="flex flex-col gap-2">
          <HowDidItGo craving={craving} onSaved={onAnswered} />
          <button type="button" onClick={() => onOpen(craving)} className="self-start text-xs font-semibold" style={{ color: "var(--primary)" }}>
            {t("craving.edit")}
          </button>
        </div>
      ))}
    </div>
  );
}

const DOT_STYLE: Record<Dot, { background: string; border: string }> = {
  full: { background: "var(--primary)", border: "var(--primary)" },
  half: { background: "color-mix(in srgb, var(--primary) 40%, transparent)", border: "var(--primary)" },
  empty: { background: "transparent", border: "var(--border)" },
  warm: { background: "var(--series-5)", border: "var(--series-5)" },
};

/** The week grid (board 14, Q7 A): a dot per day and row; swipe or step back through weeks. */
function WeekCard({
  data,
  week,
  today,
  selected,
  onSelect,
  onShift,
  canForward,
}: {
  data: WellnessOverview;
  week: { from: string; to: string; dates: string[] };
  today: string;
  selected: string;
  onSelect: (date: string) => void;
  onShift: (step: -1 | 1) => void;
  canForward: boolean;
}) {
  const t = useTranslations("MemberApp.wellness");
  const format = useFormatter();
  const touch = useRef<number | null>(null);
  const dots = useMemo(() => weekDots(data.days, week.dates), [data.days, week.dates]);
  const rows = weekRows(data.preferences.hidden_items);
  const shown = week.dates.filter((date) => date <= today);
  const nightsOnGoal = dots.sleep.filter((dot, index) => index < shown.length && dot === "full").length;
  const waterOnGoal = dots.water.filter((dot, index) => index < shown.length && dot === "full").length;
  return (
    <section
      aria-label={t("week.title")}
      className="rounded-3xl p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      onTouchStart={(event) => {
        touch.current = event.touches[0]?.clientX ?? null;
      }}
      onTouchEnd={(event) => {
        const start = touch.current;
        const end = event.changedTouches[0]?.clientX;
        touch.current = null;
        if (start === null || end === undefined) return;
        if (end - start > 50) onShift(-1);
        else if (start - end > 50 && canForward) onShift(1);
      }}
    >
      <div className="mb-3 flex items-center justify-between gap-2">
        <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {canForward
            ? t("week.range", {
                from: format.dateTime(new Date(`${week.from}T12:00:00`), { day: "numeric", month: "short" }),
                to: format.dateTime(new Date(`${week.to}T12:00:00`), { day: "numeric", month: "short" }),
              })
            : t("week.title")}
        </p>
        <div className="flex gap-1">
          <button type="button" aria-label={t("week.previous")} onClick={() => onShift(-1)} className="h-8 w-8 rounded-full" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            ‹
          </button>
          <button type="button" aria-label={t("week.next")} disabled={!canForward} onClick={() => onShift(1)} className="h-8 w-8 rounded-full disabled:opacity-40" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            ›
          </button>
        </div>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full border-separate" style={{ borderSpacing: "0 6px" }}>
          <thead>
            <tr>
              <th className="sr-only">{t("week.item")}</th>
              {week.dates.map((date) => (
                <th key={date} scope="col" className="text-center text-[11px] font-semibold" style={{ color: date === selected ? "var(--primary)" : "var(--dim)" }}>
                  <button type="button" onClick={() => onSelect(date)} disabled={!editable(date, today)} className="disabled:cursor-default">
                    {format.dateTime(new Date(`${date}T12:00:00`), { weekday: "narrow" })}
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row}>
                <th scope="row" className="pe-2 text-start text-xs font-semibold" style={{ color: "var(--text)" }}>
                  {t(`item.${row}`)}
                </th>
                {dots[row].map((dot, index) => (
                  <td key={week.dates[index]} className="text-center">
                    <span
                      className="inline-block h-3.5 w-3.5 rounded-full"
                      role="img"
                      aria-label={t(`week.dot.${dot}`)}
                      style={{ background: DOT_STYLE[dot].background, border: `1.5px solid ${DOT_STYLE[dot].border}` }}
                    />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>
        {t("week.line", { nights: nightsOnGoal, water: waterOnGoal, days: shown.length })}
      </p>
    </section>
  );
}

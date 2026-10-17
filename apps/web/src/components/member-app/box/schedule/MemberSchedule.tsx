"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useLocale, useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";

import { fetchMyEntitlement } from "@/api/my-finance";
import { fetchBookablePlaces } from "@/api/places";
import { CLASS_LEVELS, fetchSchedule, type ScheduleSlot } from "@/api/schedule";
import { FilterChipRow, type FilterChip } from "@/components/filters/FilterChipRow";
import { formatLocalIsoDate, parseLocalDate } from "@/components/schedule/calendar-window";
import { includesGuestPasses, localizeMemberBookingError } from "@/components/schedule/member-booking";
import { useSession } from "@/components/session-provider";
import { useOutboxCommand } from "@/hooks/useOutboxCommand";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { OFFLINE_COMMAND_OUTBOX_EVENT } from "@/lib/offline-command-outbox";
import { organizationTopic, subscribeToTopic } from "@/lib/realtime";

import { ClassRow } from "./ClassRow";
import { ClassSheet } from "./ClassSheet";
import { MONTH_GRID_DAYS, MonthGrid, monthGridStart, shiftMonth, type DayCount } from "./MonthGrid";
import {
  DEFAULT_SCHEDULE_FILTERS,
  activeFilterCount,
  atLocation,
  isBookedByMe,
  matchesScheduleFilters,
  nextMatch,
  type ScheduleFilters,
  type SpotsFilter,
} from "./schedule-filters";
import { ScheduleFiltersPage } from "./ScheduleFiltersPage";
import { useSchedulePreferences } from "./use-schedule-preferences";
import { WeekStrip } from "./WeekStrip";

/**
 * Both views read the six-week month grid around the selected date, so
 * switching views needs no fetch and the «next match» can look ahead.
 */
type ScheduleView = "day" | "month";

function addDays(isoDate: string, days: number) {
  const date = parseLocalDate(isoDate);
  date.setDate(date.getDate() + days);
  return formatLocalIsoDate(date);
}

function localDay(iso: string) {
  return formatLocalIsoDate(new Date(iso));
}

/**
 * Box › Πρόγραμμα for members (plan §5a): location in the title, the filter
 * chip row, the week strip and one day of classes.
 */
export function MemberSchedule({ initialOpenSlotId = null }: { initialOpenSlotId?: string | null }) {
  const t = useTranslations("BoxSchedule");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const { membership } = useSelectedMembershipRole();
  const organizationId = membership?.organization.id ?? null;
  const prefs = useSchedulePreferences(token, organizationId);
  const submitCommand = useOutboxCommand();

  const [selectedDate, setSelectedDate] = useState(() => formatLocalIsoDate(new Date()));
  const [view, setView] = useState<ScheduleView>("day");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [openSlotId, setOpenSlotId] = useState<string | null>(initialOpenSlotId);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  // The grid starts on the Monday of the 1st, so the selected day's week is always inside it.
  const windowStart = monthGridStart(selectedDate);
  const windowQuery = useQuery({
    queryKey: ["member-schedule", organizationId, windowStart],
    enabled: Boolean(token && organizationId),
    queryFn: () =>
      fetchSchedule(token!, {
        startAt: parseLocalDate(windowStart).toISOString(),
        endAt: parseLocalDate(addDays(windowStart, MONTH_GRID_DAYS)).toISOString(),
        days: 7,
        classTypeIds: [],
      }),
  });
  const { refetch } = windowQuery;
  const reload = useCallback(() => void refetch(), [refetch]);

  const placesQuery = useQuery({
    queryKey: ["bookable-places", token],
    enabled: Boolean(token),
    queryFn: () => fetchBookablePlaces(token!),
    staleTime: 5 * 60_000,
  });
  const entitlementQuery = useQuery({
    queryKey: ["my-entitlement", token, organizationId],
    enabled: Boolean(token && organizationId),
    queryFn: () => fetchMyEntitlement(token!),
  });

  useEffect(() => {
    if (!token) return;
    const topic = organizationTopic(token, "schedule");
    if (!topic) return;
    return subscribeToTopic(token, topic, { "schedule:refresh": reload });
  }, [reload, token]);

  useEffect(() => {
    const onOutbox = (event: Event) => {
      const detail = (event as CustomEvent<{ kind?: string; delivered?: boolean }>).detail;
      if (detail?.delivered && detail.kind?.startsWith("booking.")) reload();
    };
    window.addEventListener(OFFLINE_COMMAND_OUTBOX_EVENT, onOutbox);
    return () => window.removeEventListener(OFFLINE_COMMAND_OUTBOX_EVENT, onOutbox);
  }, [reload]);

  const data = windowQuery.data;
  const slots = useMemo(() => data?.slots ?? [], [data]);
  const classTypes = useMemo(() => (data?.class_types ?? []).filter((type) => !type.archived_at), [data]);
  const coaches = useMemo(() => new Map((data?.coaches ?? []).map((coach) => [coach.id, coach.nickname])), [data]);
  const gymPlaces = useMemo(
    () => (placesQuery.data ?? []).filter((place) => place.organization.id === organizationId),
    [organizationId, placesQuery.data],
  );
  const locationNames = useMemo(
    () => new Map((data?.locations ?? []).map((location) => [location.id, location.name])),
    [data],
  );

  // Plan §5a decision 8: the home location is the default, not a limit.
  const locationId = useMemo(() => {
    const ids = new Set(gymPlaces.map((place) => place.id));
    if (prefs.locationId !== undefined && (prefs.locationId === null || ids.has(prefs.locationId))) {
      return prefs.locationId;
    }
    const home = membership?.home_location_id;
    return home && ids.has(home) ? home : null;
  }, [gymPlaces, membership?.home_location_id, prefs.locationId]);
  const location = gymPlaces.find((place) => place.id === locationId) ?? null;
  const severalLocations = gymPlaces.length > 1;
  const canSwitchPlace = (placesQuery.data ?? []).length > 1;

  const filters = prefs.filters;
  const setFilters = prefs.setFilters;
  const update = (patch: Partial<ScheduleFilters>) => setFilters({ ...filters, ...patch });
  const matching = useMemo(
    () => slots.filter((slot) => atLocation(slot, locationId) && matchesScheduleFilters(slot, filters)),
    [filters, locationId, slots],
  );
  const daySlots = matching
    .filter((slot) => localDay(slot.scheduled_at) === selectedDate)
    .sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at));
  const dayCounts = useMemo(() => {
    const counts = new Map<string, DayCount>();
    matching.forEach((slot) => {
      const day = localDay(slot.scheduled_at);
      const count = counts.get(day) ?? { total: 0, mine: 0 };
      counts.set(day, { total: count.total + 1, mine: count.mine + (isBookedByMe(slot) ? 1 : 0) });
    });
    return counts;
  }, [matching]);
  const dayEnd = parseLocalDate(addDays(selectedDate, 1));
  const upcoming = daySlots.length === 0 ? nextMatch(matching, dayEnd) : null;
  const openSlot = slots.find((slot) => slot.id === openSlotId) ?? null;
  const activeCount = activeFilterCount(filters);

  const chips: FilterChip[] = [
    {
      key: "type",
      kind: "menu",
      label: t("chipType"),
      options: classTypes.map((type) => ({ value: type.id, label: type.name })),
      selected: filters.classTypeIds,
      multiple: true,
      onChange: (classTypeIds) => update({ classTypeIds }),
    },
    {
      key: "kind",
      kind: "menu",
      label: t("chipKind"),
      options: [
        { value: "class", label: t("kindClass") },
        { value: "event", label: t("kindEvent") },
      ],
      selected: filters.kind === "all" ? [] : [filters.kind],
      multiple: false,
      onChange: ([kind]) => update({ kind: (kind as ScheduleFilters["kind"]) ?? "all" }),
    },
    {
      key: "spots",
      kind: "menu",
      label: t("chipSpots"),
      options: (["open", "full_waitlist", "full"] as const).map((value) => ({ value, label: t(`spots_${value}`) })),
      selected: filters.spots === "all" ? [] : [filters.spots],
      multiple: false,
      onChange: ([spots]) => update({ spots: (spots as SpotsFilter) ?? "all" }),
    },
    {
      key: "package",
      kind: "toggle",
      label: t("chipPackage"),
      active: filters.packageOnly,
      onToggle: () => update({ packageOnly: !filters.packageOnly }),
    },
    {
      key: "level",
      kind: "menu",
      label: t("chipLevel"),
      options: CLASS_LEVELS.map((value) => ({ value, label: t(`level_${value}`) })),
      selected: filters.levels,
      multiple: true,
      onChange: (levels) => update({ levels: levels as ScheduleFilters["levels"] }),
    },
  ];

  async function book(slot: ScheduleSlot) {
    setBusy(true);
    setActionError(null);
    try {
      // ADR-120: booking requests go through the durable outbox.
      const outcome = await submitCommand("booking.request", { slotId: slot.id, label: slot.name });
      setNotice(outcome.status === "queued" ? i18n("outboxQueuedNotice") : null);
      setOpenSlotId(null);
      if (outcome.status === "delivered") reload();
    } catch (error) {
      setActionError(localizeMemberBookingError(error, i18n, locale, "book"));
    } finally {
      setBusy(false);
    }
  }

  const title = (
    <header className="flex flex-col gap-0.5">
      <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>
        {t("title")}
      </h1>
      {canSwitchPlace ? (
        <Link
          href="/box/schedule/location"
          aria-label={t("changeLocation")}
          className="flex w-fit items-center gap-1 text-sm font-semibold"
          style={{ color: "var(--text-soft)" }}
        >
          {location?.name ?? (severalLocations ? t("allLocations") : membership?.organization.name)}
          <span aria-hidden="true" style={{ color: "var(--dim)" }}>
            ▾
          </span>
        </Link>
      ) : null}
    </header>
  );

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-3 px-4 pb-6 pt-4">
      {title}

      <FilterChipRow
        ariaLabel={t("filtersAria")}
        activeCount={activeCount}
        onOpenFilters={() => setFiltersOpen(true)}
        onClear={() => setFilters(DEFAULT_SCHEDULE_FILTERS)}
        chips={chips}
      />

      <ViewSwitch
        view={view}
        selectedDate={selectedDate}
        onToggle={() => setView(view === "day" ? "month" : "day")}
        onShiftMonth={(months) => setSelectedDate(shiftMonth(selectedDate, months))}
      />

      {view === "month" ? (
        <MonthGrid
          selectedDate={selectedDate}
          counts={dayCounts}
          onSelect={(day) => {
            setSelectedDate(day);
            setView("day");
          }}
        />
      ) : (
        <WeekStrip selectedDate={selectedDate} onSelect={setSelectedDate} />
      )}

      {notice ? (
        <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }}>
          {notice}
        </p>
      ) : null}
      {actionError ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
          {actionError}
        </p>
      ) : null}

      <section aria-live="polite" hidden={view === "month"} className="flex flex-col gap-2">
        {windowQuery.isError ? (
          <div className="flex flex-col items-center gap-3 py-10 text-center">
            <p className="text-base font-bold" style={{ color: "var(--text)" }}>
              {t("loadFailed")}
            </p>
            <button
              type="button"
              onClick={reload}
              className="min-h-10 rounded-full px-5 text-sm font-bold"
              style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
            >
              {t("retry")}
            </button>
          </div>
        ) : windowQuery.isPending || !prefs.ready ? (
          Array.from({ length: 4 }, (_, index) => (
            <div key={index} className="h-16 animate-pulse rounded-2xl" style={{ background: "var(--panel)" }} />
          ))
        ) : daySlots.length > 0 ? (
          daySlots.map((slot) => (
            <ClassRow
              key={slot.id}
              slot={slot}
              coachName={slot.coach_user_id ? coaches.get(slot.coach_user_id) ?? null : null}
              locationName={
                !locationId && severalLocations && slot.location_id ? locationNames.get(slot.location_id) ?? null : null
              }
              onOpen={() => setOpenSlotId(slot.id)}
            />
          ))
        ) : (
          <EmptyDay
            date={selectedDate}
            next={upcoming}
            onJump={(slot) => {
              setSelectedDate(localDay(slot.scheduled_at));
              setOpenSlotId(null);
            }}
          />
        )}
      </section>

      {filtersOpen ? (
        <ScheduleFiltersPage
          filters={filters}
          onChange={setFilters}
          onClose={() => setFiltersOpen(false)}
          classTypes={classTypes}
          coaches={data?.coaches ?? []}
          resultCount={matching.length}
        />
      ) : null}

      {openSlot ? (
        <ClassSheet
          key={openSlot.id}
          slot={openSlot}
          coachName={openSlot.coach_user_id ? coaches.get(openSlot.coach_user_id) ?? null : null}
          locations={data?.locations ?? []}
          accessToken={token ?? ""}
          guestsIncluded={includesGuestPasses(entitlementQuery.data?.entitlement)}
          busy={busy}
          error={actionError}
          onBook={() => void book(openSlot)}
          onClose={() => {
            setOpenSlotId(null);
            setActionError(null);
          }}
          onChanged={reload}
          onCancelled={({ lateCancellation }) => {
            setNotice(lateCancellation ? i18n("mbLateCancellationNotice") : null);
            setOpenSlotId(null);
            reload();
          }}
        />
      ) : null}
    </main>
  );
}

/**
 * The month name above the calendar is the view switch (board 2, Q2): tap it
 * for the month grid, tap again for the day. The month view adds arrows.
 */
function ViewSwitch({
  view,
  selectedDate,
  onToggle,
  onShiftMonth,
}: {
  view: ScheduleView;
  selectedDate: string;
  onToggle: () => void;
  onShiftMonth: (months: number) => void;
}) {
  const t = useTranslations("BoxSchedule");
  const locale = useLocale();
  const month = new Intl.DateTimeFormat(locale, { month: "long", year: "numeric" }).format(parseLocalDate(selectedDate));
  const arrow = "grid h-9 w-9 place-items-center rounded-full text-lg";

  return (
    <div className="flex items-center justify-between gap-2">
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={view === "month"}
        aria-label={view === "day" ? t("showMonth", { month }) : t("showDay", { month })}
        className="flex min-h-9 items-center gap-1 text-base font-bold"
        style={{ color: "var(--text)" }}
      >
        <span className="first-letter:uppercase">{month}</span>
        <span aria-hidden="true" className="text-xs" style={{ color: "var(--dim)" }}>
          {view === "day" ? "▾" : "▴"}
        </span>
      </button>
      {view === "month" ? (
        <span className="flex gap-1">
          <button
            type="button"
            onClick={() => onShiftMonth(-1)}
            aria-label={t("previousMonth")}
            className={arrow}
            style={{ color: "var(--dim)" }}
          >
            <span aria-hidden="true">‹</span>
          </button>
          <button
            type="button"
            onClick={() => onShiftMonth(1)}
            aria-label={t("nextMonth")}
            className={arrow}
            style={{ color: "var(--dim)" }}
          >
            <span aria-hidden="true">›</span>
          </button>
        </span>
      ) : null}
    </div>
  );
}

function EmptyDay({
  date,
  next,
  onJump,
}: {
  date: string;
  next: ScheduleSlot | null;
  onJump: (slot: ScheduleSlot) => void;
}) {
  const t = useTranslations("BoxSchedule");
  const locale = useLocale();
  const day = new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long" }).format(
    parseLocalDate(date),
  );
  const when = next
    ? new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(
        new Date(next.scheduled_at),
      )
    : null;

  return (
    <div className="flex flex-col items-center gap-1.5 px-4 py-12 text-center">
      <p className="text-xl font-extrabold" style={{ color: "var(--text)" }}>
        {t("emptyDay")}
      </p>
      <p className="text-base font-semibold first-letter:uppercase" style={{ color: "var(--text-soft)" }}>
        {day}
      </p>
      {next && when ? (
        <button
          type="button"
          onClick={() => onJump(next)}
          className="mt-4 text-xs underline-offset-4 hover:underline"
          style={{ color: "var(--dim)" }}
        >
          {t("nextMatch", { when, name: next.name })}
        </button>
      ) : null}
    </div>
  );
}

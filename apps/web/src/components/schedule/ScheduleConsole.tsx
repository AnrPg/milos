"use client";




import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  createScheduleSlot,
  createScheduleSlotsAt,
  createScheduleSeries,
  deleteScheduleSlot,
  fetchSchedule,
  updateScheduleSlot,
  type ClassAction,
  type SeriesEditScope,
  type ScheduleBooking,
  type ClassTypeRecord,
  type ScheduleLocation,
  type ScheduleSlot,
  type ScheduleSlotPayload,
} from "@/api/schedule";
import { fetchMyEntitlement, type EffectiveEntitlement } from "@/api/my-finance";
import { fetchAdminSettings, type SchedulingSettings } from "@/api/settings";
import { useSession } from "@/components/session-provider";
import { ViewModeSelector } from "@/components/calendar/ViewModeSelector";
import { BookingModal } from "@/components/schedule/BookingModal";
import { CalendarView } from "@/components/schedule/CalendarView";
import { buildScheduleWindow } from "@/components/schedule/calendar-window";
import { SlotPopup } from "@/components/schedule/SlotPopup";
import { ClassActionDialog, useClassActionSummary } from "@/components/schedule/ClassState";
import { SeriesScopePicker, seriesScopeReady } from "@/components/schedule/SeriesScopePicker";
import { SlotLocationSelect } from "@/components/schedule/SlotLocationSelect";
import { SlotSpaceSelect } from "@/components/schedule/SlotSpaceSelect";
import { AppliesToBranches, defaultAppliesTo, showsAppliesTo } from "@/components/admin/AppliesToBranches";
import { listAdminLocations } from "@/api/facility";
import { useQuery } from "@tanstack/react-query";
import { OpenGymCheckIn } from "@/components/schedule/OpenGymCheckIn";
import { includesGuestPasses, localizeMemberBookingError } from "@/components/schedule/member-booking";
import { TypeFilterChips } from "@/components/schedule/TypeFilterChips";
import { FirstClassTypeDialog } from "@/components/schedule/FirstClassTypeDialog";
import { useOutboxCommand } from "@/hooks/useOutboxCommand";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { OFFLINE_COMMAND_OUTBOX_EVENT } from "@/lib/offline-command-outbox";
import { organizationTopic, subscribeToTopic } from "@/lib/realtime";
import { useScheduleStore } from "@/stores/schedule";
import { IntegerInput } from "@/components/integer-input";
import { DurationLimitField } from "@/components/schedule/BookingRuleFields";
import { fetchGymStaff } from "@/api/staff";
import { coachOptions } from "@/components/admin/staff-home";
import { can } from "@/lib/role-navigation";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import {
  fieldBorder,
  formErrorsFrom,
  invalidFieldProps,
  stillApplies,
  type FormErrors,
} from "@/lib/form-errors";
import { defaultClassStart, earliestPickable, startsInPast, todayKey } from "@/components/schedule/slot-time";

/** A class may name its coach (ADR-100). */
type ClassPayload = ScheduleSlotPayload & { coach_user_id?: string | null };
import { PageHeader } from "@/components/PageHeader";
import { dateTimeLocalInZone, dateTimeLocalToIso, formatInZone, zoneLabel, zonedText } from "@/lib/zoned-time";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { ContextualWorkoutCreator } from "@/components/workouts/creation/ContextualWorkoutCreator";
import { WodPicker } from "@/components/schedule/WodPicker";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { DateInput, TimeInput, DateTimeInput } from "@/components/ui/DateInput";
import { FRESHNESS } from "@/lib/query-policy";

/** The class form's fields, as the API names them (ADR-214 errors land on these). */
const SLOT_FIELDS = [
  "class_type_id",
  "name",
  "master_workout_id",
  "scheduled_at",
  "duration_minutes",
  "capacity",
  "booking_timeout_minutes",
  "location_id",
  "space_id",
  "coach_user_id",
] as const;
type SlotField = (typeof SLOT_FIELDS)[number];

type SlotEditorState = {
  slotId: string | null;
  /** ADR-200: the edited class's series; its edit can reach further. */
  seriesId?: string | null;
  values: ClassPayload;
  /** The start the class had when the form opened: an unchanged past start may stay. */
  originalScheduledAt?: string | null;
  /** ADR-214: what the last save got wrong, and the values it sent. */
  errors?: FormErrors<SlotField>;
  sent?: ClassPayload;
};

const SERIES_FIELDS = [
  "class_type_id",
  "name",
  "master_workout_id",
  "duration_minutes",
  "starts_on",
  "ends_on",
  "local_start_time",
  "weekdays",
  "excluded_dates",
  "location_id",
  "space_id",
  "coach_user_id",
  "capacity",
  "booking_timeout_minutes",
  "timezone",
] as const;
type SeriesField = (typeof SERIES_FIELDS)[number];

type SeriesEditorState = {
  values: Omit<ClassPayload, "scheduled_at">;
  startDate: string;
  endDate: string;
  time: string;
  weekdays: number[];
  excludedDates: string;
  timezone: string;
  /** ADR-214: what the last save got wrong, and the values it sent. */
  errors?: FormErrors<SeriesField>;
  sent?: Partial<Record<SeriesField, unknown>>;
};

/** What staff were adding when the gym turned out to have no class type yet. */
type PendingCreate = { kind: "slot"; isoDate: string } | { kind: "series" };

/** Which open class form «+ New WOD» writes a WOD for. */
type NewWodTarget = "slot" | "series";

const hasActiveClassType = (types: ClassTypeRecord[]) => types.some((type) => !type.archived_at);

/** A real "YYYY-MM-DD" day (2026-02-30 is not one). */
function isCalendarDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

// ADR-179: a class's date and time are typed on the gym's clock (`zone`),
// whatever the device's zone; without one, the device's clock.
function formatDateTimeLocal(isoString: string, zone: string | null) {
  return dateTimeLocalInZone(isoString, zone);
}

function toIsoDateTime(localValue: string, zone: string | null) {
  return dateTimeLocalToIso(localValue, zone);
}

function defaultSlotValues(
  isoDate: string,
  classTypes: ClassTypeRecord[],
  defaults?: SchedulingSettings,
  zone: string | null = null,
): ScheduleSlotPayload {
  // ADR-214: 09:00 on the gym's clock, or the next open half hour once
  // that has passed, never a start the API refuses as past.
  const date = defaultClassStart(isoDate, zone);

  return {
    // ADR-176: the WOD can be linked later; until then the class is a draft.
    master_workout_id: null,
    class_type_id: classTypes.find((type) => !type.archived_at)?.id ?? "",
    name: classTypes.find((type) => !type.archived_at)?.name ?? "",
    duration_minutes: 60,
    scheduled_at: date.toISOString(),
    capacity: defaults?.default_capacity ?? 12,
    auto_approve: defaults?.default_auto_approve ?? false,
    booking_timeout_minutes: defaults ? defaults.default_booking_timeout_minutes ?? null : 60,
  };
}

export function ScheduleConsole({
  initialOpenSlotId = null,
  pageTitle,
}: {
  initialOpenSlotId?: string | null;
  pageTitle?: string;
} = {}) {
  const i18n = useUiTranslations();
  const t = useTranslations("Schedule");
  const common = useTranslations("Common");
  const branchT = useTranslations("BranchScope");
  const rulesT = useTranslations("BookingRules");
  const locale = useLocale();
  const { tokens } = useSession();
  const { days, setDays, openDay, shiftWindow, resetWindow, startDate, classTypeIds, setClassTypeIds } = useScheduleStore();
  const [schedule, setSchedule] = useState<ScheduleSlot[]>([]);
  const [classTypes, setClassTypes] = useState<ClassTypeRecord[]>([]);
  const [locations, setLocations] = useState<ScheduleLocation[]>([]);
  const [entitlement, setEntitlement] = useState<EffectiveEntitlement | null | undefined>(undefined);
  const [notice, setNotice] = useState<string | null>(null);
  // ADR-186 §8: «Ισχύει για» on a new class or series, and what it created.
  const [createBranches, setCreateBranches] = useState<string[]>([]);
  // ADR-200: how far an edit to a class of a series goes.
  const [seriesScope, setSeriesScope] = useState<SeriesEditScope>({ scope: "this" });
  const [created, setCreated] = useState<{ kind: "classes" | "series"; items: { id: string; label: string; slotId?: string }[] } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const submitCommand = useOutboxCommand();
  const [selectedSlot, setSelectedSlot] = useState<ScheduleSlot | null>(null);
  // ADR-200 §2: the pause / cancel / delete waiting for its confirmation.
  const [classAction, setClassAction] = useState<{ slot: ScheduleSlot; action: ClassAction } | null>(null);
  const classActionSummary = useClassActionSummary();
  const [bookingTarget, setBookingTarget] = useState<ScheduleSlot | null>(null);
  const [resolveTarget, setResolveTarget] = useState<{ booking: ScheduleBooking; action: "approve" | "reject" } | null>(
    null,
  );
  const [resolveMessage, setResolveMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [editor, setEditor] = useState<SlotEditorState | null>(null);
  const [seriesEditor, setSeriesEditor] = useState<SeriesEditorState | null>(null);
  const [pendingCreate, setPendingCreate] = useState<PendingCreate | null>(null);
  const [reopenSlotId, setReopenSlotId] = useState<string | null>(null);
  const [newWodFor, setNewWodFor] = useState<NewWodTarget | null>(null);
  const [schedulingDefaults, setSchedulingDefaults] = useState<SchedulingSettings | undefined>();
  // ADR-176: series follow the gym's time zone, not the editing device's.
  const [gymTimeZone, setGymTimeZone] = useState<string | null>(null);
  // ADR-179: the gym's clock (staff settings first, else the membership's).
  const membershipZone = useOrganizationTimeZone();
  const gymZone = gymTimeZone ?? membershipZone;
  const appliedMobileDefault = useRef(false);
  const initialOpenHandledRef = useRef(false);
  const { role, isLoading: roleLoading, membership } = useSelectedMembershipRole();
  const canManageSchedule = can(membership, "manage_schedule");

  const isAdmin = role === "admin";
  // ADR-097: the class editors offer a location only when the gym has one.
  const adminLocationsQuery = useQuery({
    queryKey: ["admin", "locations"],
    queryFn: () => listAdminLocations(tokens!.access_token),
    enabled: isAdmin && Boolean(tokens?.access_token),
    staleTime: FRESHNESS.reference,
  });
  const adminLocations = adminLocationsQuery.data ?? [];
  const manyBranches = showsAppliesTo(adminLocations);
  const locationName = (id: string | null | undefined) => adminLocations.find((location) => location.id === id)?.name ?? "";
  const coachesQuery = useQuery({
    queryKey: ["staff", "members"],
    queryFn: () => fetchGymStaff(tokens!.access_token),
    enabled: canManageSchedule && Boolean(tokens?.access_token),
    staleTime: FRESHNESS.reference,
  });
  const coaches = coachOptions(coachesQuery.data ?? []);
  const isMemberSurface = !roleLoading && !isAdmin;
  const calendarWindow = useMemo(() => buildScheduleWindow(startDate, days, gymZone), [days, gymZone, startDate]);
  const title = pageTitle ?? t("title");

  const loadSchedule = useCallback(async () => {
    if (!tokens?.access_token) return null;

    setLoading(true);
    setError(null);

    try {
      const window = await fetchSchedule(tokens.access_token, {
        startAt: calendarWindow.queryStartAt,
        endAt: calendarWindow.queryEndAt,
        days,
        classTypeIds,
      });

      const nextSlots = Array.isArray(window.slots) ? window.slots : [];
      const nextClassTypes = Array.isArray(window.class_types) ? window.class_types : [];

      setSchedule(nextSlots);
      setClassTypes(nextClassTypes);
      setLocations(Array.isArray(window.locations) ? window.locations : []);
      return nextSlots;
    } catch (loadError) {
      setError(loadError instanceof Error ? localizeError(loadError, i18n) : t("failedToLoadSchedule"));
      return null;
    } finally {
      setLoading(false);
    }
  }, [calendarWindow.queryEndAt, calendarWindow.queryStartAt, classTypeIds, days, i18n, t, tokens]);

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      void loadSchedule();
    });

    return () => window.cancelAnimationFrame(frame);
  }, [loadSchedule]);

  useEffect(() => {
    const handleOutbox = (event: Event) => {
      const detail = (event as CustomEvent<{ kind?: string; delivered?: boolean }>).detail;
      if (detail?.delivered && detail.kind?.startsWith("booking.")) {
        setNotice(null);
        void loadSchedule();
      }
    };

    window.addEventListener(OFFLINE_COMMAND_OUTBOX_EVENT, handleOutbox);
    return () => window.removeEventListener(OFFLINE_COMMAND_OUTBOX_EVENT, handleOutbox);
  }, [loadSchedule]);

  useEffect(() => {
    if (!tokens?.access_token) return;

    const topic = organizationTopic(tokens.access_token, "schedule");
    if (!topic) return;

    return subscribeToTopic(tokens.access_token, topic, {
      "schedule:refresh": () => {
        void loadSchedule();
      },
    });
  }, [loadSchedule, tokens?.access_token]);

  useEffect(() => {
    const accessToken = tokens?.access_token;

    if (!isAdmin || typeof accessToken !== "string") return;

    const token = accessToken;

    let cancelled = false;

    // The WOD picker searches the library on demand (WodPicker); the page no
    // longer loads every workout.
    void fetchAdminSettings(token)
      .then((settings) => {
        if (!cancelled) {
          setSchedulingDefaults(settings.scheduling);
          setGymTimeZone(settings.time_zone?.timezone ?? null);
        }
      })
      .catch(() => undefined);

    return () => {
      cancelled = true;
    };
  }, [isAdmin, tokens?.access_token]);

  // The member's package decides whether guest and open-gym actions appear.
  useEffect(() => {
    const accessToken = tokens?.access_token;
    if (!isMemberSurface || typeof accessToken !== "string") return;

    let cancelled = false;

    void fetchMyEntitlement(accessToken)
      .then((response) => {
        if (!cancelled) setEntitlement(response.entitlement);
      })
      .catch(() => {
        if (!cancelled) setEntitlement(null);
      });

    return () => {
      cancelled = true;
    };
  }, [isMemberSurface, tokens?.access_token]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (appliedMobileDefault.current) return;
    if (!window.matchMedia("(max-width: 767px)").matches || days !== 7) return;

    appliedMobileDefault.current = true;
    const frame = window.requestAnimationFrame(() => setDays(3));

    return () => window.cancelAnimationFrame(frame);
  }, [days, setDays]);

  useEffect(() => {
    if (!initialOpenSlotId || initialOpenHandledRef.current || schedule.length === 0) return;
    const slot = schedule.find((s) => s.id === initialOpenSlotId);
    if (slot) {
      initialOpenHandledRef.current = true;
      const frame = window.requestAnimationFrame(() => setSelectedSlot(slot));

      return () => window.cancelAnimationFrame(frame);
    }
  }, [initialOpenSlotId, schedule]);

  // Reopen the class the coach left from once the schedule has it.
  useEffect(() => {
    if (!reopenSlotId || loading) return;
    const slot = schedule.find((item) => item.id === reopenSlotId);
    if (!slot) return;
    const frame = window.requestAnimationFrame(() => {
      setReopenSlotId(null);
      setSelectedSlot(slot);
    });
    return () => window.cancelAnimationFrame(frame);
  }, [loading, reopenSlotId, schedule]);

  const classTypeName = (id: string | null | undefined) => classTypes.find((type) => type.id === id)?.name ?? null;

  // «+ New WOD» opens the editor over the class form, which stays as it is;
  // the published WOD becomes the form's WOD (saved with the class).
  function assignNewWod(target: NewWodTarget, workoutId: string) {
    if (target === "slot") {
      setEditor((current) => (current ? { ...current, values: { ...current.values, master_workout_id: workoutId } } : current));
    } else {
      setSeriesEditor((current) => (current ? { ...current, values: { ...current.values, master_workout_id: workoutId } } : current));
    }
  }

  function newWodTargetLabel(target: NewWodTarget) {
    const values = target === "slot" ? editor?.values : seriesEditor?.values;
    const name = values?.name?.trim() || classTypeName(values?.class_type_id) || null;
    if (target === "series") return name;
    const when = editor?.values.scheduled_at ? formatInZone(editor.values.scheduled_at, gymZone, locale, "day-time") : null;
    return [name, when].filter(Boolean).join(" · ") || null;
  }

  // ADR-214: "it is 23:40 at the gym now", on the gym's clock.
  const gymNowText = () => formatInZone(new Date(), gymZone, locale, "time");
  const pastStartMessage = () => i18n("formErrClassStartPassed", { time: gymNowText(), zone: zoneLabel(gymZone) });

  /** The class's start is in the past and was set or changed in this form. */
  function editorStartProblem(state: SlotEditorState): string | null {
    const changed = !state.slotId || state.values.scheduled_at !== state.originalScheduledAt;
    return changed && startsInPast(state.values.scheduled_at) ? pastStartMessage() : null;
  }

  function slotErrorsFrom(reason: unknown, fallback: string): FormErrors<SlotField> {
    return formErrorsFrom(reason, i18n, SLOT_FIELDS, {
      fallback,
      overrides: { scheduled_at: (message) => (message === "must be in the future" ? pastStartMessage() : null) },
    });
  }

  const editorDateValue = useMemo(() => {
    if (!editor) return "";
    return formatDateTimeLocal(editor.values.scheduled_at, gymZone);
  }, [editor, gymZone]);

  // ADR-214: each field's reason, from the last save or from what the form
  // can already tell (a start that has passed).
  const editorStart = editor ? editorStartProblem(editor) : null;
  const editorFieldErrors: Partial<Record<SlotField, string>> = editor
    ? { ...stillApplies(editor.errors, editor.sent, editor.values), ...(editorStart ? { scheduled_at: editorStart } : {}) }
    : {};
  const seriesFieldErrors: Partial<Record<SeriesField, string>> = seriesEditor
    ? { ...stillApplies(seriesEditor.errors, seriesEditor.sent, seriesFieldValues(seriesEditor)), ...seriesProblems(seriesEditor) }
    : {};
  const slotInputStyle = (field: SlotField) => ({
    background: "var(--panel-muted)",
    border: fieldBorder(editorFieldErrors[field]),
    color: "var(--text)",
  });
  const seriesInputStyle = (field: SeriesField) =>
    seriesFieldErrors[field] ? { border: fieldBorder(seriesFieldErrors[field]) } : undefined;

  async function handleBook() {
    if (!tokens?.access_token || !bookingTarget) return;

    setBusy(true);

    try {
      // ADR-120: booking requests go through the durable outbox so an offline
      // request is replayed once, with the same idempotency key, on reconnect.
      const outcome = await submitCommand("booking.request", {
        slotId: bookingTarget.id,
        label: bookingTarget.name,
      });
      setNotice(outcome.status === "queued" ? i18n("outboxQueuedNotice") : null);
      setBookingTarget(null);
      setSelectedSlot(null);
      if (outcome.status === "delivered") await loadSchedule();
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? localizeMemberBookingError(requestError, i18n, locale, "book")
          : t("failedToCreateBooking"),
      );
    } finally {
      setBusy(false);
    }
  }

  // Waitlist and guest changes keep the popup open on the refreshed class.
  async function refreshSelectedSlot() {
    const refreshedSlots = await loadSchedule();
    if (!refreshedSlots) return;
    setSelectedSlot((current) =>
      current ? refreshedSlots.find((slot) => slot.id === current.id) ?? current : current,
    );
  }

  async function handleResolve() {
    if (!tokens?.access_token || !resolveTarget) return;

    setBusy(true);

    try {
      const outcome = await submitCommand(
        resolveTarget.action === "approve" ? "booking.approve" : "booking.reject",
        {
          bookingId: resolveTarget.booking.id,
          adminMessage: resolveMessage.trim() || null,
          label: resolveTarget.booking.user_nickname ?? null,
        },
      );
      setNotice(outcome.status === "queued" ? i18n("outboxQueuedNotice") : null);

      const refreshedSlots = outcome.status === "delivered" ? await loadSchedule() : null;
      setResolveTarget(null);
      setResolveMessage("");

      if (selectedSlot && refreshedSlots) {
        const refreshed = refreshedSlots.find((slot) => slot.id === selectedSlot.id);
        if (refreshed) setSelectedSlot(refreshed);
      }
    } catch (requestError) {
      setError(requestError instanceof Error ? localizeError(requestError, i18n) : t("failedToResolveBooking"));
    } finally {
      setBusy(false);
    }
  }

  async function saveSlot() {
    if (!tokens?.access_token || !editor) return;
    // ADR-214: a past start is explained on the field; nothing is sent.
    if (editorStartProblem(editor)) return;

    setBusy(true);
    const sent = editor.values;

    try {
      if (!editor.slotId && manyBranches) {
        const slots = await createScheduleSlotsAt(tokens.access_token, editor.values, createBranches);
        setCreated({
          kind: "classes",
          items: slots.map((slot) => ({ id: slot.id, slotId: slot.id, label: `${slot.name} · ${locationName(slot.location_id)}` })),
        });
        setNotice(slots.some((slot) => !slot.master_workout_id) ? i18n("classDraftSavedNotice") : null);
        setEditor(null);
        await loadSchedule();
        return;
      }

      const { slot: saved, updatedCount } = editor.slotId
        ? await updateScheduleSlot(tokens.access_token, editor.slotId, editor.values, editor.seriesId ? seriesScope : { scope: "this" })
        : { slot: await createScheduleSlot(tokens.access_token, editor.values), updatedCount: 1 };

      // ADR-176: say plainly that a class without a WOD stays hidden.
      setNotice(
        updatedCount > 1
          ? t("seriesClassesUpdated", { count: updatedCount })
          : !saved.master_workout_id && !saved.class_series_id
            ? i18n("classDraftSavedNotice")
            : null,
      );
      setEditor(null);
      await loadSchedule();
    } catch (requestError) {
      // ADR-214: the reasons stay in the form, on the fields they concern.
      const errors = slotErrorsFrom(requestError, t("failedToSaveSlot"));
      setEditor((current) => (current ? { ...current, errors, sent } : current));
    } finally {
      setBusy(false);
    }
  }

  async function removeEditedSlot() {
    if (!tokens?.access_token || !editor?.slotId) return;

    setBusy(true);

    try {
      await deleteScheduleSlot(tokens.access_token, editor.slotId);
      const deletedSlotId = editor.slotId;
      setEditor(null);

      if (selectedSlot?.id === deletedSlotId) {
        setSelectedSlot(null);
      }

      await loadSchedule();
    } catch (requestError) {
      const message =
        requestError instanceof ApiError ? localizeError(requestError, i18n) : t("failedToDeleteSlot");
      setEditor((current) => (current ? { ...current, errors: { fields: {}, message }, sent: current.values } : current));
    } finally {
      setBusy(false);
    }
  }

  // ADR-176: a class needs a class type, never a WOD. A gym without any type
  // names its first one inline and goes on to the class it was adding.
  function openCreateEditor(isoDate: string, types: ClassTypeRecord[] = classTypes) {
    if (!hasActiveClassType(types)) {
      setPendingCreate({ kind: "slot", isoDate });
      return;
    }

    setCreateBranches(defaultAppliesTo(adminLocations));
    setEditor({
      slotId: null,
      values: defaultSlotValues(isoDate, types, schedulingDefaults, gymZone),
    });
  }

  function openSeriesEditor(types: ClassTypeRecord[] = classTypes) {
    if (!hasActiveClassType(types)) {
      setPendingCreate({ kind: "series" });
      return;
    }

    const base = defaultSlotValues(startDate, types, schedulingDefaults, gymZone);
    // ADR-214: a series starts today at the earliest, on the gym's calendar.
    const seriesStart = startDate < todayKey(gymZone) ? todayKey(gymZone) : startDate;
    setCreateBranches(defaultAppliesTo(adminLocations));
    setSeriesEditor({
      values: {
        master_workout_id: null,
        class_type_id: base.class_type_id,
        name: base.name,
        duration_minutes: base.duration_minutes,
        capacity: base.capacity,
        auto_approve: base.auto_approve,
        booking_timeout_minutes: base.booking_timeout_minutes,
      },
      startDate: seriesStart,
      endDate: "",
      time: "09:00",
      weekdays: [new Date(`${seriesStart}T12:00:00`).getDay() || 7],
      excludedDates: "",
      timezone: gymZone ?? (Intl.DateTimeFormat().resolvedOptions().timeZone || "Etc/UTC"),
    });
  }

  async function saveSeries() {
    if (!seriesEditor || !tokens?.access_token) return;
    if (Object.keys(seriesProblems(seriesEditor)).length > 0) return;
    setBusy(true);
    setError(null);
    const sent = seriesFieldValues(seriesEditor);
    try {
      const result = await createScheduleSeries(tokens.access_token, {
        ...seriesEditor.values,
        timezone: seriesEditor.timezone,
        starts_on: seriesEditor.startDate,
        ends_on: seriesEditor.endDate || null,
        local_start_time: `${seriesEditor.time}:00`,
        weekdays: seriesEditor.weekdays,
        excluded_dates: seriesEditor.excludedDates
          .split(",")
          .map((date) => date.trim())
          .filter(Boolean),
        ...(manyBranches ? { location_id: null, location_ids: createBranches } : {}),
      });
      if (!result.series.occurrence_count) setError(i18n("featureNoSeriesOccurrences"));
      if (manyBranches) {
        const list = result.series_list ?? [result.series];
        setCreated({
          kind: "series",
          items: list.map((series) => ({ id: series.id, label: `${seriesEditor.values.name} · ${locationName(series.location_id)}` })),
        });
      }
      setSeriesEditor(null);
      await loadSchedule();
    } catch (reason) {
      const errors = formErrorsFrom(reason, i18n, SERIES_FIELDS, { fallback: i18n("featureSeriesCreateFailed") });
      setSeriesEditor((current) => (current ? { ...current, errors, sent } : current));
    } finally {
      setBusy(false);
    }
  }

  /** The series form's values keyed as the API names them (to tell a corrected field). */
  function seriesFieldValues(state: SeriesEditorState): Partial<Record<SeriesField, unknown>> {
    return {
      ...state.values,
      starts_on: state.startDate,
      ends_on: state.endDate,
      local_start_time: state.time,
      weekdays: state.weekdays,
      excluded_dates: state.excludedDates,
      timezone: state.timezone,
    };
  }

  /** ADR-214: what the series form can tell before sending, in plain words. */
  function seriesProblems(state: SeriesEditorState): Partial<Record<SeriesField, string>> {
    const problems: Partial<Record<SeriesField, string>> = {};
    if (!state.startDate) problems.starts_on = i18n("formErrRequired");
    else if (state.startDate < todayKey(gymZone)) problems.starts_on = i18n("formErrDayPassed");
    if (state.endDate && state.startDate && state.endDate < state.startDate) problems.ends_on = i18n("formErrEndsBeforeStart");
    if (state.weekdays.length === 0) problems.weekdays = i18n("formErrPickWeekday");
    const badDates = state.excludedDates
      .split(",")
      .map((date) => date.trim())
      .filter((date) => date && !isCalendarDate(date));
    if (badDates.length > 0) problems.excluded_dates = i18n("formErrExcludedDates", { dates: badDates.join(", ") });
    return problems;
  }

  function slotValues(slot: ScheduleSlot): ClassPayload {
    return {
      master_workout_id: slot.master_workout_id,
      class_type_id: slot.class_type_id,
      name: slot.name,
      duration_minutes: slot.duration_minutes,
      scheduled_at: slot.scheduled_at,
      capacity: slot.capacity,
      auto_approve: slot.auto_approve,
      booking_timeout_minutes: slot.booking_timeout_minutes,
      location_id: slot.location_id ?? null,
      space_id: slot.space_id ?? null,
      ...(canManageSchedule ? { coach_user_id: slot.coach_user_id ?? null } : {}),
    };
  }

  function openUpdateEditor(slot: ScheduleSlot) {
    setSeriesScope({ scope: "this" });
    setEditor({ slotId: slot.id, seriesId: slot.class_series_id ?? null, values: slotValues(slot), originalScheduledAt: slot.scheduled_at });
  }

  // A new class like this one, outside any series, at its branch; staff
  // usually change only its date.
  function openDuplicateEditor(slot: ScheduleSlot) {
    setSelectedSlot(null);
    setCreateBranches(slot.location_id ? [slot.location_id] : defaultAppliesTo(adminLocations));
    // A class already past is copied to the same time on the next week ahead.
    let at = new Date(slot.scheduled_at);
    while (at.getTime() <= Date.now()) at = new Date(at.getTime() + 7 * 86_400_000);
    setEditor({ slotId: null, seriesId: null, values: { ...slotValues(slot), scheduled_at: at.toISOString() } });
  }

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-7xl space-y-8">
        <PageHeader title={title} />


        <section className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_auto] xl:items-center">
            <div className="min-w-0">
              <TypeFilterChips classTypes={classTypes} value={classTypeIds} onChange={setClassTypeIds} />
            </div>

            <div className="flex flex-wrap justify-start gap-3 xl:justify-end">
              <ViewModeSelector
                ariaLabel={t("calendarView")}
                onChange={setDays}
                options={[
                  { value: 1, label: t("dayViewShort"), accessibleLabel: t("dayView") },
                  { value: 3, label: i18n("message3d34f9efc"), accessibleLabel: t("threeDayView") },
                  { value: 7, label: i18n("message7dfd4a4c2"), accessibleLabel: t("weekView") },
                  { value: 30, label: i18n("mo91e885d"), accessibleLabel: t("monthView") },
                ]}
                value={days}
              />

              <div className="flex gap-2">
                {(
                  [
                    [t("previous"), () => shiftWindow(-1)],
                    [t("today"), resetWindow],
                    [t("next"), () => shiftWindow(1)],
                  ] as const
                ).map(([label, handler]) => (
                  <button
                    key={label}
                    className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                    style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                    onClick={handler}
                    type="button"
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </section>

        {isAdmin ? (
          <div className="flex justify-end">
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} onClick={() => openSeriesEditor()}>{i18n("featureCreateClassSeries")}</button>
          </div>
        ) : null}

        {isMemberSurface && tokens?.access_token ? (
          <OpenGymCheckIn accessToken={tokens.access_token} entitlement={entitlement} />
        ) : null}

        {error ? (
          <ErrorNotice>
            {error}
          </ErrorNotice>
        ) : null}

        {created ? (
          <div
            className="flex items-start justify-between gap-3 rounded-[1.6rem] px-5 py-4 text-sm"
            role="status"
            style={{ background: "color-mix(in srgb, var(--success) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--success) 28%, transparent)", color: "var(--text-soft)" }}
          >
            <div>
              <p className="font-semibold" style={{ color: "var(--text)" }}>
                {created.kind === "classes"
                  ? branchT("createdClasses", { count: created.items.length })
                  : branchT("createdSeries", { count: created.items.length })}
              </p>
              <ul className="mt-1 flex flex-wrap gap-x-3 gap-y-1">
                {created.items.map((item) => (
                  <li key={item.id}>
                    {item.slotId ? (
                      <button
                        type="button"
                        className="underline underline-offset-2"
                        style={{ color: "var(--primary)" }}
                        onClick={() => setReopenSlotId(item.slotId!)}
                      >
                        {item.label}
                      </button>
                    ) : (
                      <span>{item.label}</span>
                    )}
                  </li>
                ))}
              </ul>
            </div>
            <button className="shrink-0 text-xs font-semibold" style={{ color: "var(--dim)" }} onClick={() => setCreated(null)} type="button">
              {common("close")}
            </button>
          </div>
        ) : null}

        {notice ? (
          <div
            className="flex items-start justify-between gap-3 rounded-[1.6rem] px-5 py-4 text-sm"
            role="status"
            style={{ background: "color-mix(in srgb, var(--info) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--info) 28%, transparent)", color: "var(--text-soft)" }}
          >
            <span>{notice}</span>
            <button
              className="shrink-0 text-xs font-semibold"
              style={{ color: "var(--dim)" }}
              onClick={() => setNotice(null)}
              type="button"
            >
              {common("close")}
            </button>
          </div>
        ) : null}

        {loading ? (
          <section className="rounded-[2rem] p-10 text-center text-sm font-semibold uppercase tracking-[0.24em]" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--dim)" }}>
            {t("loading")}
          </section>
        ) : (
          <CalendarView
            days={days}
            isAdmin={isAdmin}
            locations={locations}
            onCreateSlot={(isoDate) => openCreateEditor(isoDate)}
            onOpenDay={openDay}
            onSelectSlot={setSelectedSlot}
            slots={schedule}
            startDate={startDate}
            timeZone={gymZone}
          />
        )}
      </div>

      {newWodFor ? (
        <ContextualWorkoutCreator
          target={newWodTargetLabel(newWodFor)}
          onPublished={(workoutId) => assignNewWod(newWodFor, workoutId)}
          onClose={() => setNewWodFor(null)}
        />
      ) : null}

      {selectedSlot ? (
        <SlotPopup
          key={selectedSlot.id}
          timeZone={gymZone}
          accessToken={tokens?.access_token ?? ""}
          isAdmin={isAdmin}
          onApproveBooking={(booking) => {
            setResolveMessage("");
            setResolveTarget({ booking, action: "approve" });
          }}
          onBook={() => setBookingTarget(selectedSlot)}
          guestsIncluded={includesGuestPasses(entitlement)}
          canProgramVariations={can(membership, "manage_coaching")}
          locations={locations}
          onCancelBooking={({ lateCancellation }) => {
            setNotice(lateCancellation ? i18n("mbLateCancellationNotice") : null);
            void loadSchedule();
          }}
          onSlotChanged={() => void refreshSelectedSlot()}
          onClose={() => setSelectedSlot(null)}
          onClassAction={(action) => setClassAction({ slot: selectedSlot, action })}
          onEdit={() => openUpdateEditor(selectedSlot)}
          onDuplicate={() => openDuplicateEditor(selectedSlot)}
          onRejectBooking={(booking) => {
            setResolveMessage("");
            setResolveTarget({ booking, action: "reject" });
          }}
          slot={selectedSlot}
        />
      ) : null}

      {classAction && tokens?.access_token ? (
        <ClassActionDialog
          token={tokens.access_token}
          slot={classAction.slot}
          action={classAction.action}
          classDate={dateTimeLocalInZone(classAction.slot.scheduled_at, gymZone).slice(0, 10)}
          onClose={() => setClassAction(null)}
          onDone={(result) => {
            setClassAction(null);
            setNotice(classActionSummary(result) || null);
            if (selectedSlot && result.deleted_ids.includes(selectedSlot.id)) {
              setSelectedSlot(null);
              void loadSchedule();
            } else {
              void refreshSelectedSlot();
            }
          }}
        />
      ) : null}

      {bookingTarget ? (
        <BookingModal
          busy={busy}
          confirmLabel={t("confirmBooking")}
          description={t("bookClassDescription", {
            workoutTitle: bookingTarget.workout?.title ?? t("thisSlot"),
            scheduledAt: zonedText(bookingTarget.scheduled_at, gymZone, locale, {
              weekday: "long",
              month: "short",
              day: "numeric",
              hour: "numeric",
              minute: "2-digit",
            }),
          })}
          onCancel={() => setBookingTarget(null)}
          onConfirm={() => void handleBook()}
          title={t("bookClassSlot")}
        />
      ) : null}

      {resolveTarget ? (
        <BookingModal
          busy={busy}
          confirmLabel={resolveTarget.action === "approve" ? t("approveBooking") : t("rejectBooking")}
          description={t("resolveBookingDescription", {
            memberName: resolveTarget.booking.user_nickname ?? t("thisMember"),
            action: resolveTarget.action === "approve" ? t("approve") : t("reject"),
          })}
          inputLabel={t("adminMessage")}
          inputPlaceholder={t("optionalNoteForMember")}
          inputValue={resolveMessage}
          onCancel={() => {
            setResolveTarget(null);
            setResolveMessage("");
          }}
          onConfirm={() => void handleResolve()}
          onInputChange={setResolveMessage}
          title={resolveTarget.action === "approve" ? t("approveBooking") : t("rejectBooking")}
        />
      ) : null}

      {editor ? (
        <Dialog
          onClose={() => setEditor(null)}
          error={editor.errors?.message}
          eyebrow={t("adminSlotEditor")}
          title={editor.slotId ? t("editScheduledClass") : t("createScheduledClass")}
          size="2xl"
          footer={
            <div className="flex w-full flex-wrap justify-between gap-3">
              {editor.slotId ? (
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 25%, transparent)", color: "var(--primary)" }}
                  onClick={() => void removeEditedSlot()}
                  type="button"
                >
                  {t("deleteSlot")}
                </button>
              ) : <span />}

              <div className="flex gap-3">
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                  style={{ background: "var(--border)", color: "var(--text-soft)" }}
                  onClick={() => setEditor(null)}
                  type="button"
                >
                  {common("cancel")}
                </button>
                <button
                  className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "var(--text)", color: "var(--bg)" }}
                  disabled={busy || !editor.values.class_type_id || !editor.values.name.trim() || Boolean(editorFieldErrors.scheduled_at) || (!editor.slotId && manyBranches && createBranches.length === 0) || (Boolean(editor.seriesId) && !seriesScopeReady(seriesScope))}
                  onClick={() => void saveSlot()}
                  type="button"
                >
                  {busy ? common("saving") : editor.slotId ? t("saveChanges") : t("createSlot")}
                </button>
              </div>
            </div>
          }
        >
            <div className="grid gap-4 md:grid-cols-2">
              {[
                { label: t("classType"), type: "select-type" as const, field: "class_type_id" as const },
                { label: i18n("featureClassName"), type: "name" as const, field: "name" as const },
                { label: t("workout"), type: "select" as const, field: "master_workout_id" as const },
                { label: t("scheduledAt"), type: "datetime" as const, field: "scheduled_at" as const },
                { label: i18n("featureDurationMinutes"), type: "number-duration" as const, field: "duration_minutes" as const },
                { label: t("capacity"), type: "number-cap" as const, field: "capacity" as const },
                { label: rulesT("approvalWaitLabel"), type: "number-timeout" as const, field: "booking_timeout_minutes" as const },
              ].map(({ label, type, field }) =>
                type === "number-timeout" ? (
                  // ADR-226: how long a request waits for staff; only without auto-approval.
                  <div key={label} className="md:col-span-2" style={{ color: "var(--muted)" }}>
                    <DurationLimitField
                      testId="slot-approval-wait"
                      label={label}
                      help={rulesT("approvalWaitClassHelp")}
                      noLimitLabel={rulesT("approvalWaitNoLimit")}
                      value={editor.values.booking_timeout_minutes}
                      min={1}
                      max={10080}
                      fallback={60}
                      inputStyle={slotInputStyle(field)}
                      inputProps={invalidFieldProps(editorFieldErrors[field], `slot-error-${field}`)}
                      onChange={(timeoutMinutes) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, booking_timeout_minutes: timeoutMinutes } } : current,
                        )
                      }
                    />
                    <FieldError id={`slot-error-${field}`}>{editorFieldErrors[field]}</FieldError>
                  </div>
                ) : type === "select" ? (
                  <div key={label} className="md:col-span-2">
                    <WodPicker
                      label={label}
                      token={tokens?.access_token ?? ""}
                      date={dateTimeLocalInZone(editor.values.scheduled_at, gymZone).slice(0, 10) || null}
                      classTypeId={editor.values.class_type_id || null}
                      classTypeName={classTypeName(editor.values.class_type_id)}
                      value={editor.values.master_workout_id ?? null}
                      onChange={(workoutId) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, master_workout_id: workoutId } } : current,
                        )
                      }
                      onCreateNew={() => setNewWodFor("slot")}
                    />
                    <FieldError id="slot-error-master_workout_id">{editorFieldErrors.master_workout_id}</FieldError>
                  </div>
                ) : (
                <label key={label} className="space-y-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
                  <span>{label}</span>
                  {type === "select-type" ? (
                    <Select
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={slotInputStyle(field)}
                      {...invalidFieldProps(editorFieldErrors[field], `slot-error-${field}`)}
                      onValueChange={(value) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, class_type_id: value } } : current,
                        )
                      }
                      value={editor.values.class_type_id}
                    >
                      {classTypes.filter((classType) => !classType.archived_at).map((option) => (
                        <option key={option.id} value={option.id}>{option.name}</option>
                      ))}
                    </Select>
                  ) : type === "name" ? (
                    <input
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={slotInputStyle(field)}
                      {...invalidFieldProps(editorFieldErrors[field], `slot-error-${field}`)}
                      maxLength={120}
                      onChange={(event) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, name: event.target.value } } : current,
                        )
                      }
                      value={editor.values.name}
                    />
                  ) : type === "number-duration" ? (
                    <IntegerInput
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={slotInputStyle(field)}
                      {...invalidFieldProps(editorFieldErrors[field], `slot-error-${field}`)}
                      min={1}
                      max={1440}
                      emptyValue={1}
                      onValueChange={(durationMinutes) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, duration_minutes: durationMinutes ?? 1 } } : current,
                        )
                      }
                      value={editor.values.duration_minutes}
                    />
                  ) : type === "datetime" ? (
                    <>
                    <DateTimeInput
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={slotInputStyle(field)}
                      {...invalidFieldProps(editorFieldErrors[field], `slot-error-${field}`)}
                      onValueChange={(value) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, scheduled_at: toIsoDateTime(value, gymZone) } } : current,
                        )
                      }
                      value={editorDateValue}
                      min={editor.slotId ? undefined : earliestPickable(gymZone)}
                    />
                    {gymZone ? (
                      <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{i18n("zonedTimeGymClock", { zone: zoneLabel(gymZone) })}</p>
                    ) : null}
                    </>
                  ) : type === "number-cap" ? (
                    <IntegerInput
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={slotInputStyle(field)}
                      {...invalidFieldProps(editorFieldErrors[field], `slot-error-${field}`)}
                      min={1}
                      emptyValue={1}
                      onValueChange={(capacity) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, capacity: capacity ?? 1 } } : current,
                        )
                      }
                      value={editor.values.capacity}
                    />
                  ) : null}
                  <FieldError id={`slot-error-${field}`}>{editorFieldErrors[field]}</FieldError>
                </label>
                ),
              )}
            </div>

            <label className="mt-4 flex items-center gap-3 text-sm font-semibold" style={{ color: "var(--muted)" }}>
              <input
                checked={editor.values.auto_approve}
                onChange={(event) =>
                  setEditor((current) =>
                    current ? { ...current, values: { ...current.values, auto_approve: event.target.checked } } : current,
                  )
                }
                type="checkbox"
              />
              {t("autoApproveBookingsForThisSlot")}
            </label>

            {!editor.slotId && manyBranches ? (
              <div className="mt-4">
                <AppliesToBranches
                  kind="each"
                  locations={adminLocations}
                  value={createBranches}
                  onChange={(value) => setCreateBranches(value === "all" ? defaultAppliesTo(adminLocations) : value)}
                />
              </div>
            ) : (
              // Editing: the class stays one class at one branch.
              <SlotLocationSelect
                className="mt-4 block space-y-2 text-sm font-semibold"
                locations={adminLocations}
                onChange={(locationId) =>
                  setEditor((current) => (current ? { ...current, values: { ...current.values, location_id: locationId } } : current))
                }
                selectClassName="w-full rounded-2xl px-4 py-3 outline-none"
                selectStyle={slotInputStyle("location_id")}
                value={editor.values.location_id}
              />
            )}
            <FieldError id="slot-error-location_id">{editorFieldErrors.location_id}</FieldError>
            {/* ADR-202: the space of the class, among those of its branch. */}
            <SlotSpaceSelect
              className="mt-4 block space-y-2 text-sm font-semibold"
              locationIds={!editor.slotId && manyBranches ? createBranches : [editor.values.location_id]}
              onChange={(spaceId) => setEditor((current) => (current ? { ...current, values: { ...current.values, space_id: spaceId } } : current))}
              selectClassName="w-full rounded-2xl px-4 py-3 outline-none"
              selectStyle={slotInputStyle("space_id")}
              value={editor.values.space_id}
            />
            <FieldError id="slot-error-space_id">{editorFieldErrors.space_id}</FieldError>

            {canManageSchedule ? (
              <ClassCoachSelect
                className="mt-4 block space-y-2 text-sm font-semibold"
                coaches={coaches}
                label={i18n("rhClassCoach")}
                noneLabel={i18n("rhNoCoach")}
                onChange={(coachUserId) =>
                  setEditor((current) => (current ? { ...current, values: { ...current.values, coach_user_id: coachUserId } } : current))
                }
                selectClassName="w-full rounded-2xl px-4 py-3 outline-none"
                selectStyle={slotInputStyle("coach_user_id")}
                value={editor.values.coach_user_id}
              />
            ) : null}
            <FieldError id="slot-error-coach_user_id">{editorFieldErrors.coach_user_id}</FieldError>

            {editor.slotId && editor.seriesId ? (
              <SeriesScopePicker
                className="mt-4"
                value={seriesScope}
                onChange={setSeriesScope}
                classDate={dateTimeLocalInZone(editor.values.scheduled_at, gymZone).slice(0, 10)}
              />
            ) : null}

        </Dialog>
      ) : null}

      {pendingCreate && tokens?.access_token ? (
        <FirstClassTypeDialog
          token={tokens.access_token}
          onClose={() => setPendingCreate(null)}
          onCreated={(classType) => {
            const next = [...classTypes, classType];
            const pending = pendingCreate;
            setClassTypes(next);
            setPendingCreate(null);
            if (pending.kind === "slot") openCreateEditor(pending.isoDate, next);
            else openSeriesEditor(next);
          }}
        />
      ) : null}

      {seriesEditor ? (
        <Dialog
          onClose={() => setSeriesEditor(null)}
          error={seriesEditor.errors?.message}
          eyebrow={i18n("featureBatchScheduling")}
          title={i18n("featureCreateClassSeries")}
          size="2xl"
          footer={
            <div className="flex gap-2"><button type="button" className="rounded-full px-4 py-2" onClick={() => setSeriesEditor(null)}>{common("cancel")}</button><button type="button" disabled={busy || Object.keys(seriesProblems(seriesEditor)).length > 0 || !seriesEditor.values.name.trim() || (manyBranches && createBranches.length === 0)} className="rounded-full px-5 py-2 font-semibold disabled:opacity-50" style={{ background: "var(--text)", color: "var(--bg)" }} onClick={() => void saveSeries()}>{busy ? i18n("featureCreating") : i18n("featureCreateSeries")}</button></div>
          }
        >
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="text-sm font-semibold">{i18n("featureClassType")}<Select className="mt-2 w-full rounded-xl px-3 py-2" style={seriesInputStyle("class_type_id")} {...invalidFieldProps(seriesFieldErrors.class_type_id, "series-error-class_type_id")} value={seriesEditor.values.class_type_id} onValueChange={(value) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, class_type_id: value } })}>{classTypes.filter((item) => !item.archived_at).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</Select><FieldError id="series-error-class_type_id">{seriesFieldErrors.class_type_id}</FieldError></label>
              <label className="text-sm font-semibold">{i18n("featureClassName")}<input className="mt-2 w-full rounded-xl px-3 py-2" style={seriesInputStyle("name")} {...invalidFieldProps(seriesFieldErrors.name, "series-error-name")} maxLength={120} value={seriesEditor.values.name} onChange={(event) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, name: event.target.value } })} /><FieldError id="series-error-name">{seriesFieldErrors.name}</FieldError></label>
              <div className="sm:col-span-2">
                <WodPicker
                  label={i18n("classSeriesWod")}
                  token={tokens?.access_token ?? ""}
                  date={seriesEditor.startDate || null}
                  classTypeId={seriesEditor.values.class_type_id || null}
                  classTypeName={classTypeName(seriesEditor.values.class_type_id)}
                  value={seriesEditor.values.master_workout_id ?? null}
                  onChange={(workoutId) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, master_workout_id: workoutId } })}
                  onCreateNew={() => setNewWodFor("series")}
                  noneHint={i18n("classSeriesWodHint")}
                />
                <FieldError id="series-error-master_workout_id">{seriesFieldErrors.master_workout_id}</FieldError>
              </div>
              <label className="text-sm font-semibold">{i18n("featureDurationMinutes")}<IntegerInput className="mt-2 w-full rounded-xl px-3 py-2" style={seriesInputStyle("duration_minutes")} {...invalidFieldProps(seriesFieldErrors.duration_minutes, "series-error-duration_minutes")} min={1} max={1440} value={seriesEditor.values.duration_minutes} emptyValue={1} onValueChange={(durationMinutes) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, duration_minutes: durationMinutes ?? 1 } })} /><FieldError id="series-error-duration_minutes">{seriesFieldErrors.duration_minutes}</FieldError></label>
              <label className="text-sm font-semibold">{i18n("featureStarts")}<DateInput className="mt-2 w-full rounded-xl px-3 py-2" style={seriesInputStyle("starts_on")} {...invalidFieldProps(seriesFieldErrors.starts_on, "series-error-starts_on")} min={todayKey(gymZone)} value={seriesEditor.startDate} onValueChange={(value) => setSeriesEditor({ ...seriesEditor, startDate: value })} /><FieldError id="series-error-starts_on">{seriesFieldErrors.starts_on}</FieldError></label>
              <label className="text-sm font-semibold">{i18n("featureEndsOptional")}<DateInput className="mt-2 w-full rounded-xl px-3 py-2" style={seriesInputStyle("ends_on")} {...invalidFieldProps(seriesFieldErrors.ends_on, "series-error-ends_on")} min={seriesEditor.startDate} value={seriesEditor.endDate} onValueChange={(value) => setSeriesEditor({ ...seriesEditor, endDate: value })} /><FieldError id="series-error-ends_on">{seriesFieldErrors.ends_on}</FieldError></label>
              <label className="text-sm font-semibold">{i18n("featureTime")}<TimeInput className="mt-2 w-full rounded-xl px-3 py-2" style={seriesInputStyle("local_start_time")} {...invalidFieldProps(seriesFieldErrors.local_start_time, "series-error-local_start_time")} value={seriesEditor.time} onValueChange={(value) => setSeriesEditor({ ...seriesEditor, time: value })} /><FieldError id="series-error-local_start_time">{seriesFieldErrors.local_start_time}</FieldError></label>
              <div className="text-sm font-semibold">{i18n("featureWeekdays")}<div className="mt-2 flex flex-wrap gap-2">{["featureMonday", "featureTuesday", "featureWednesday", "featureThursday", "featureFriday", "featureSaturday", "featureSunday"].map((key, index) => { const day = index + 1; return <button key={key} type="button" aria-pressed={seriesEditor.weekdays.includes(day)} className="rounded-full px-3 py-2 text-xs" style={{ background: seriesEditor.weekdays.includes(day) ? "var(--primary)" : "var(--panel-muted)", color: seriesEditor.weekdays.includes(day) ? "var(--primary-contrast)" : "var(--text-soft)" }} onClick={() => setSeriesEditor({ ...seriesEditor, weekdays: seriesEditor.weekdays.includes(day) ? seriesEditor.weekdays.filter((item) => item !== day) : [...seriesEditor.weekdays, day] })}>{i18n(key)}</button>; })}</div><FieldError id="series-error-weekdays">{seriesFieldErrors.weekdays}</FieldError></div>
              <label className="text-sm font-semibold">{i18n("featureExcludedDates")}<input className="mt-2 w-full rounded-xl px-3 py-2" style={seriesInputStyle("excluded_dates")} {...invalidFieldProps(seriesFieldErrors.excluded_dates, "series-error-excluded_dates")} placeholder="2026-08-15, 2026-12-25" value={seriesEditor.excludedDates} onChange={(event) => setSeriesEditor({ ...seriesEditor, excludedDates: event.target.value })} /><span className="mt-1 block text-xs font-normal" style={{ color: "var(--dim)" }}>{i18n("featureCommaSeparatedDates")}</span><FieldError id="series-error-excluded_dates">{seriesFieldErrors.excluded_dates}</FieldError></label>
              {manyBranches ? (
                <div className="sm:col-span-2">
                  <AppliesToBranches
                    kind="each"
                    locations={adminLocations}
                    value={createBranches}
                    onChange={(value) => setCreateBranches(value === "all" ? defaultAppliesTo(adminLocations) : value)}
                  />
                </div>
              ) : (
                <SlotLocationSelect className="text-sm font-semibold" locations={adminLocations} onChange={(locationId) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, location_id: locationId } })} selectClassName="mt-2 w-full rounded-xl px-3 py-2" selectStyle={seriesInputStyle("location_id")} value={seriesEditor.values.location_id} />
              )}
              <FieldError id="series-error-location_id">{seriesFieldErrors.location_id}</FieldError>
              <SlotSpaceSelect className="text-sm font-semibold" locationIds={manyBranches ? createBranches : [seriesEditor.values.location_id]} onChange={(spaceId) => setSeriesEditor((current) => (current ? { ...current, values: { ...current.values, space_id: spaceId } } : current))} selectClassName="mt-2 w-full rounded-xl px-3 py-2" selectStyle={seriesInputStyle("space_id")} value={seriesEditor.values.space_id} />
              <FieldError id="series-error-space_id">{seriesFieldErrors.space_id}</FieldError>
              {canManageSchedule ? <ClassCoachSelect className="text-sm font-semibold" coaches={coaches} label={i18n("rhClassCoach")} noneLabel={i18n("rhNoCoach")} onChange={(coachUserId) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, coach_user_id: coachUserId } })} selectClassName="mt-2 w-full rounded-xl px-3 py-2" selectStyle={seriesInputStyle("coach_user_id")} value={seriesEditor.values.coach_user_id} /> : null}
              <FieldError id="series-error-coach_user_id">{seriesFieldErrors.coach_user_id}</FieldError>
              <label className="text-sm font-semibold">{i18n("featureTimezone")}<input className="mt-2 w-full rounded-xl px-3 py-2" readOnly value={seriesEditor.timezone} /><FieldError id="series-error-timezone">{seriesFieldErrors.timezone}</FieldError></label>
            </div>
            <details className="mt-5 rounded-2xl p-4" open={seriesFieldErrors.capacity || seriesFieldErrors.booking_timeout_minutes ? true : undefined} style={{ background: "var(--panel-muted)" }}><summary className="cursor-pointer text-sm font-semibold">{i18n("featureOptionalClassSettings")}</summary><div className="mt-4 grid gap-3 sm:grid-cols-3"><label className="text-xs">{i18n("featureCapacity")}<IntegerInput className="mt-1 w-full rounded-xl px-3 py-2" style={seriesInputStyle("capacity")} {...invalidFieldProps(seriesFieldErrors.capacity, "series-error-capacity")} min={1} value={seriesEditor.values.capacity} emptyValue={1} onValueChange={(capacity) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, capacity: capacity ?? 1 } })} /><FieldError id="series-error-capacity">{seriesFieldErrors.capacity}</FieldError></label><div className="text-xs sm:col-span-3"><DurationLimitField testId="series-approval-wait" label={rulesT("approvalWaitLabel")} help={rulesT("approvalWaitClassHelp")} noLimitLabel={rulesT("approvalWaitNoLimit")} value={seriesEditor.values.booking_timeout_minutes} min={1} max={10080} fallback={60} inputStyle={seriesInputStyle("booking_timeout_minutes")} inputProps={invalidFieldProps(seriesFieldErrors.booking_timeout_minutes, "series-error-booking_timeout_minutes")} onChange={(timeoutMinutes) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, booking_timeout_minutes: timeoutMinutes } })} /><FieldError id="series-error-booking_timeout_minutes">{seriesFieldErrors.booking_timeout_minutes}</FieldError></div><label className="flex items-center gap-2 text-xs"><input type="checkbox" checked={seriesEditor.values.auto_approve} onChange={(event) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, auto_approve: event.target.checked } })} />{i18n("featureAutoApprove")}</label></div></details>
        </Dialog>
      ) : null}
    </main>
  );
}

function ClassCoachSelect({
  className,
  coaches,
  label,
  noneLabel,
  onChange,
  selectClassName,
  selectStyle,
  value,
}: {
  className: string;
  coaches: Array<{ user_id: string; nickname?: string | null }>;
  label: string;
  noneLabel: string;
  onChange: (coachUserId: string | null) => void;
  selectClassName: string;
  selectStyle?: React.CSSProperties;
  value: string | null | undefined;
}) {
  return (
    <label className={className} style={selectStyle ? { color: "var(--muted)" } : undefined}>
      <span>{label}</span>
      <Select className={selectClassName} style={selectStyle} value={value ?? ""} onValueChange={(value) => onChange(value || null)}>
        <option value="">{noneLabel}</option>
        {coaches.map((coach) => (
          <option key={coach.user_id} value={coach.user_id}>{coach.nickname ?? coach.user_id}</option>
        ))}
      </Select>
    </label>
  );
}

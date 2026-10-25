"use client";




import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocale, useTranslations } from "next-intl";
import { useRouter } from "next/navigation";

import { ApiError } from "@/api/client";
import {
  createScheduleSlot,
  createScheduleSlotsAt,
  createScheduleSeries,
  linkScheduleSlotWorkout,
  deleteScheduleSlot,
  fetchSchedule,
  updateScheduleSlot,
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
import { SlotLocationSelect } from "@/components/schedule/SlotLocationSelect";
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
import { fetchGymStaff } from "@/api/staff";
import { coachOptions } from "@/components/admin/staff-home";
import { can } from "@/lib/role-navigation";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** A class may name its coach (ADR-100). */
type ClassPayload = ScheduleSlotPayload & { coach_user_id?: string | null };
import { PageHeader } from "@/components/PageHeader";
import { dateTimeLocalInZone, dateTimeLocalToIso, zoneLabel, zonedText, zonedToInstant } from "@/lib/zoned-time";
import { adminHref, useOrganizationSlug, useOrganizationTimeZone } from "@/lib/organization-slug";
import { RETURNED_WORKOUT_PARAM, newWorkoutHref } from "@/lib/workout-return";
import { WodPicker } from "@/components/schedule/WodPicker";
import { stashClassDraft, takeClassDraft } from "@/components/schedule/class-draft-handoff";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { DateInput, TimeInput, DateTimeInput } from "@/components/ui/DateInput";

type SlotEditorState = {
  slotId: string | null;
  /** ADR-200: the edited class's series; its edit can reach further. */
  seriesId?: string | null;
  values: ClassPayload;
};

type SeriesEditorState = {
  values: Omit<ClassPayload, "scheduled_at">;
  startDate: string;
  endDate: string;
  time: string;
  weekdays: number[];
  excludedDates: string;
  timezone: string;
};

/** What staff were adding when the gym turned out to have no class type yet. */
type PendingCreate = { kind: "slot"; isoDate: string } | { kind: "series" };

/** A class form left open for the WOD editor ("+ New WOD"). */
type ClassDraft =
  | { kind: "slot"; editor: SlotEditorState }
  | { kind: "series"; editor: SeriesEditorState }
  // A class without its WOD (ADR-176): the new WOD is linked to it on return.
  | { kind: "link"; slotId: string };

const hasActiveClassType = (types: ClassTypeRecord[]) => types.some((type) => !type.archived_at);

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
  const date = zonedToInstant(isoDate, "09:00", zone);

  return {
    // ADR-176: the WOD can be linked later; until then the class is a draft.
    master_workout_id: null,
    class_type_id: classTypes.find((type) => !type.archived_at)?.id ?? "",
    name: classTypes.find((type) => !type.archived_at)?.name ?? "",
    duration_minutes: 60,
    scheduled_at: date.toISOString(),
    capacity: defaults?.default_capacity ?? 12,
    auto_approve: defaults?.default_auto_approve ?? false,
    booking_timeout_minutes: defaults?.default_booking_timeout_minutes ?? 60,
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
  const locale = useLocale();
  const { tokens } = useSession();
  const { days, setDays, shiftWindow, resetWindow, startDate, classTypeIds, setClassTypeIds } = useScheduleStore();
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
  const router = useRouter();
  const organizationSlug = useOrganizationSlug();
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
  });
  const adminLocations = adminLocationsQuery.data ?? [];
  const manyBranches = showsAppliesTo(adminLocations);
  const locationName = (id: string | null | undefined) => adminLocations.find((location) => location.id === id)?.name ?? "";
  const coachesQuery = useQuery({
    queryKey: ["staff", "members"],
    queryFn: () => fetchGymStaff(tokens!.access_token),
    enabled: canManageSchedule && Boolean(tokens?.access_token),
    staleTime: 60_000,
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

  // Back from the WOD editor: reopen the class form as the coach left it, with
  // the WOD they just published (`?wod=`) chosen, then tidy the address.
  useEffect(() => {
    const url = new URL(window.location.href);
    const returnedWorkoutId = url.searchParams.get(RETURNED_WORKOUT_PARAM);
    const draft = takeClassDraft<ClassDraft>();
    if (returnedWorkoutId) {
      url.searchParams.delete(RETURNED_WORKOUT_PARAM);
      router.replace(`${url.pathname}${url.search}`, { scroll: false });
    }
    if (!draft) return;
    if (draft.kind === "link") {
      const token = tokens?.access_token;
      if (returnedWorkoutId && token) {
        void linkScheduleSlotWorkout(token, draft.slotId, returnedWorkoutId)
          .catch((reason) => setError(localizeError(reason, i18n)))
          .finally(() => setReopenSlotId(draft.slotId));
      } else {
        const frame = window.requestAnimationFrame(() => setReopenSlotId(draft.slotId));
        return () => window.cancelAnimationFrame(frame);
      }
      return;
    }
    const master_workout_id = returnedWorkoutId ?? draft.editor.values.master_workout_id;
    const frame = window.requestAnimationFrame(() => {
      if (draft.kind === "slot") setEditor({ ...draft.editor, values: { ...draft.editor.values, master_workout_id } });
      else setSeriesEditor({ ...draft.editor, values: { ...draft.editor.values, master_workout_id } });
    });
    return () => window.cancelAnimationFrame(frame);
    // Runs once on arrival; the session token is already there by then.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [router]);

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

  function createNewWod(draft: ClassDraft) {
    stashClassDraft(draft);
    router.push(newWorkoutHref(adminHref("/admin/workouts/new", organizationSlug), window.location.pathname));
  }

  const editorDateValue = useMemo(() => {
    if (!editor) return "";
    return formatDateTimeLocal(editor.values.scheduled_at, gymZone);
  }, [editor, gymZone]);

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

    setBusy(true);

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
      setError(requestError instanceof Error ? localizeError(requestError, i18n) : t("failedToSaveSlot"));
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
      setError(message);
    } finally {
      setBusy(false);
    }
  }

  async function deleteSelectedSlot() {
    if (!tokens?.access_token || !selectedSlot) return;
    if (!window.confirm(t("deleteSlot"))) return;

    setBusy(true);
    setError(null);

    try {
      await deleteScheduleSlot(tokens.access_token, selectedSlot.id);
      setSelectedSlot(null);
      await loadSchedule();
    } catch (requestError) {
      const message =
        requestError instanceof ApiError ? localizeError(requestError, i18n) : t("failedToDeleteSlot");
      setError(message);
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
      startDate,
      endDate: "",
      time: "09:00",
      weekdays: [new Date(`${startDate}T12:00:00`).getDay() || 7],
      excludedDates: "",
      timezone: gymZone ?? (Intl.DateTimeFormat().resolvedOptions().timeZone || "Etc/UTC"),
    });
  }

  async function saveSeries() {
    if (!seriesEditor || !tokens?.access_token) return;
    setBusy(true);
    setError(null);
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
      setError(reason instanceof Error ? localizeError(reason, i18n) : i18n("featureSeriesCreateFailed"));
    } finally {
      setBusy(false);
    }
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
      ...(canManageSchedule ? { coach_user_id: slot.coach_user_id ?? null } : {}),
    };
  }

  function openUpdateEditor(slot: ScheduleSlot) {
    setSeriesScope({ scope: "this" });
    setEditor({ slotId: slot.id, seriesId: slot.class_series_id ?? null, values: slotValues(slot) });
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
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} onClick={() => openSeriesEditor()}>{i18n("featureCreateSeries")}</button>
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
            onSelectSlot={setSelectedSlot}
            slots={schedule}
            startDate={startDate}
            timeZone={gymZone}
          />
        )}
      </div>

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
          onCreateWorkout={() => createNewWod({ kind: "link", slotId: selectedSlot.id })}
          locations={locations}
          onCancelBooking={({ lateCancellation }) => {
            setNotice(lateCancellation ? i18n("mbLateCancellationNotice") : null);
            void loadSchedule();
          }}
          onSlotChanged={() => void refreshSelectedSlot()}
          onClose={() => setSelectedSlot(null)}
          onDelete={() => void deleteSelectedSlot()}
          onEdit={() => openUpdateEditor(selectedSlot)}
          onDuplicate={() => openDuplicateEditor(selectedSlot)}
          onRejectBooking={(booking) => {
            setResolveMessage("");
            setResolveTarget({ booking, action: "reject" });
          }}
          slot={selectedSlot}
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
                  disabled={busy || !editor.values.class_type_id || !editor.values.name.trim() || (!editor.slotId && manyBranches && createBranches.length === 0) || (Boolean(editor.seriesId) && !seriesScopeReady(seriesScope))}
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
                { label: t("classType"), type: "select-type" as const },
                { label: i18n("featureClassName"), type: "name" as const },
                { label: t("workout"), type: "select" as const },
                { label: t("scheduledAt"), type: "datetime" as const },
                { label: i18n("featureDurationMinutes"), type: "number-duration" as const },
                { label: t("capacity"), type: "number-cap" as const },
                { label: t("timeoutMinutes"), type: "number-timeout" as const },
              ].map(({ label, type }) =>
                type === "select" ? (
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
                      onCreateNew={() => createNewWod({ kind: "slot", editor })}
                    />
                  </div>
                ) : (
                <label key={label} className="space-y-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
                  <span>{label}</span>
                  {type === "select-type" ? (
                    <Select
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
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
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
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
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
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
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                      onValueChange={(value) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, scheduled_at: toIsoDateTime(value, gymZone) } } : current,
                        )
                      }
                      value={editorDateValue}
                    />
                    {gymZone ? (
                      <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{i18n("zonedTimeGymClock", { zone: zoneLabel(gymZone) })}</p>
                    ) : null}
                    </>
                  ) : type === "number-cap" ? (
                    <IntegerInput
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                      min={1}
                      emptyValue={1}
                      onValueChange={(capacity) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, capacity: capacity ?? 1 } } : current,
                        )
                      }
                      value={editor.values.capacity}
                    />
                  ) : (
                    <IntegerInput
                      className="w-full rounded-2xl px-4 py-3 outline-none"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                      min={1}
                      emptyValue={1}
                      onValueChange={(timeoutMinutes) =>
                        setEditor((current) =>
                          current ? { ...current, values: { ...current.values, booking_timeout_minutes: timeoutMinutes ?? 1 } } : current,
                        )
                      }
                      value={editor.values.booking_timeout_minutes}
                    />
                  )}
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
                selectStyle={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={editor.values.location_id}
              />
            )}

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
                selectStyle={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={editor.values.coach_user_id}
              />
            ) : null}

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
          eyebrow={i18n("featureBatchScheduling")}
          title={i18n("featureCreateClassSeries")}
          size="2xl"
          footer={
            <div className="flex gap-2"><button type="button" className="rounded-full px-4 py-2" onClick={() => setSeriesEditor(null)}>{common("cancel")}</button><button type="button" disabled={busy || seriesEditor.weekdays.length === 0 || !seriesEditor.values.name.trim() || (manyBranches && createBranches.length === 0)} className="rounded-full px-5 py-2 font-semibold disabled:opacity-50" style={{ background: "var(--text)", color: "var(--bg)" }} onClick={() => void saveSeries()}>{busy ? i18n("featureCreating") : i18n("featureCreateSeries")}</button></div>
          }
        >
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="text-sm font-semibold">{i18n("featureClassType")}<Select className="mt-2 w-full rounded-xl px-3 py-2" value={seriesEditor.values.class_type_id} onValueChange={(value) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, class_type_id: value } })}>{classTypes.filter((item) => !item.archived_at).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</Select></label>
              <label className="text-sm font-semibold">{i18n("featureClassName")}<input className="mt-2 w-full rounded-xl px-3 py-2" maxLength={120} value={seriesEditor.values.name} onChange={(event) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, name: event.target.value } })} /></label>
              <div className="sm:col-span-2">
                <WodPicker
                  label={i18n("classSeriesWod")}
                  token={tokens?.access_token ?? ""}
                  date={seriesEditor.startDate || null}
                  classTypeId={seriesEditor.values.class_type_id || null}
                  classTypeName={classTypeName(seriesEditor.values.class_type_id)}
                  value={seriesEditor.values.master_workout_id ?? null}
                  onChange={(workoutId) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, master_workout_id: workoutId } })}
                  onCreateNew={() => createNewWod({ kind: "series", editor: seriesEditor })}
                  noneHint={i18n("classSeriesWodHint")}
                />
              </div>
              <label className="text-sm font-semibold">{i18n("featureDurationMinutes")}<IntegerInput className="mt-2 w-full rounded-xl px-3 py-2" min={1} max={1440} value={seriesEditor.values.duration_minutes} emptyValue={1} onValueChange={(durationMinutes) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, duration_minutes: durationMinutes ?? 1 } })} /></label>
              <label className="text-sm font-semibold">{i18n("featureStarts")}<DateInput className="mt-2 w-full rounded-xl px-3 py-2" value={seriesEditor.startDate} onValueChange={(value) => setSeriesEditor({ ...seriesEditor, startDate: value })} /></label>
              <label className="text-sm font-semibold">{i18n("featureEndsOptional")}<DateInput className="mt-2 w-full rounded-xl px-3 py-2" min={seriesEditor.startDate} value={seriesEditor.endDate} onValueChange={(value) => setSeriesEditor({ ...seriesEditor, endDate: value })} /></label>
              <label className="text-sm font-semibold">{i18n("featureTime")}<TimeInput className="mt-2 w-full rounded-xl px-3 py-2" value={seriesEditor.time} onValueChange={(value) => setSeriesEditor({ ...seriesEditor, time: value })} /></label>
              <div className="text-sm font-semibold">{i18n("featureWeekdays")}<div className="mt-2 flex flex-wrap gap-2">{["featureMonday", "featureTuesday", "featureWednesday", "featureThursday", "featureFriday", "featureSaturday", "featureSunday"].map((key, index) => { const day = index + 1; return <button key={key} type="button" aria-pressed={seriesEditor.weekdays.includes(day)} className="rounded-full px-3 py-2 text-xs" style={{ background: seriesEditor.weekdays.includes(day) ? "var(--primary)" : "var(--panel-muted)", color: seriesEditor.weekdays.includes(day) ? "var(--primary-contrast)" : "var(--text-soft)" }} onClick={() => setSeriesEditor({ ...seriesEditor, weekdays: seriesEditor.weekdays.includes(day) ? seriesEditor.weekdays.filter((item) => item !== day) : [...seriesEditor.weekdays, day] })}>{i18n(key)}</button>; })}</div></div>
              <label className="text-sm font-semibold">{i18n("featureExcludedDates")}<input className="mt-2 w-full rounded-xl px-3 py-2" placeholder="2026-08-15, 2026-12-25" value={seriesEditor.excludedDates} onChange={(event) => setSeriesEditor({ ...seriesEditor, excludedDates: event.target.value })} /><span className="mt-1 block text-xs font-normal" style={{ color: "var(--dim)" }}>{i18n("featureCommaSeparatedDates")}</span></label>
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
                <SlotLocationSelect className="text-sm font-semibold" locations={adminLocations} onChange={(locationId) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, location_id: locationId } })} selectClassName="mt-2 w-full rounded-xl px-3 py-2" value={seriesEditor.values.location_id} />
              )}
              {canManageSchedule ? <ClassCoachSelect className="text-sm font-semibold" coaches={coaches} label={i18n("rhClassCoach")} noneLabel={i18n("rhNoCoach")} onChange={(coachUserId) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, coach_user_id: coachUserId } })} selectClassName="mt-2 w-full rounded-xl px-3 py-2" value={seriesEditor.values.coach_user_id} /> : null}
              <label className="text-sm font-semibold">{i18n("featureTimezone")}<input className="mt-2 w-full rounded-xl px-3 py-2" readOnly value={seriesEditor.timezone} /></label>
            </div>
            <details className="mt-5 rounded-2xl p-4" style={{ background: "var(--panel-muted)" }}><summary className="cursor-pointer text-sm font-semibold">{i18n("featureOptionalClassSettings")}</summary><div className="mt-4 grid gap-3 sm:grid-cols-3"><label className="text-xs">{i18n("featureCapacity")}<IntegerInput className="mt-1 w-full rounded-xl px-3 py-2" min={1} value={seriesEditor.values.capacity} emptyValue={1} onValueChange={(capacity) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, capacity: capacity ?? 1 } })} /></label><label className="text-xs">{i18n("featureTimeoutMinutes")}<IntegerInput className="mt-1 w-full rounded-xl px-3 py-2" min={1} value={seriesEditor.values.booking_timeout_minutes} emptyValue={1} onValueChange={(timeoutMinutes) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, booking_timeout_minutes: timeoutMinutes ?? 1 } })} /></label><label className="flex items-center gap-2 text-xs"><input type="checkbox" checked={seriesEditor.values.auto_approve} onChange={(event) => setSeriesEditor({ ...seriesEditor, values: { ...seriesEditor.values, auto_approve: event.target.checked } })} />{i18n("featureAutoApprove")}</label></div></details>
        </Dialog>
      ) : null}
    </main>
  );
}

function seriesScopeReady(scope: SeriesEditScope) {
  return scope.scope !== "range" || (Boolean(scope.from) && Boolean(scope.to) && scope.from <= scope.to);
}

/**
 * ADR-200: an edit to a class of a series reaches this class, every upcoming
 * class of the series (and the classes it creates later), or the classes
 * between two dates on the gym's clock.
 */
function SeriesScopePicker({
  className,
  value,
  onChange,
  classDate,
}: {
  className: string;
  value: SeriesEditScope;
  onChange: (scope: SeriesEditScope) => void;
  classDate: string;
}) {
  const t = useTranslations("Schedule");
  const options: Array<{ scope: SeriesEditScope["scope"]; label: string }> = [
    { scope: "this", label: t("seriesScopeThis") },
    { scope: "all", label: t("seriesScopeAll") },
    { scope: "range", label: t("seriesScopeRange") },
  ];
  const range = value.scope === "range" ? value : { scope: "range" as const, from: classDate, to: classDate };

  return (
    <fieldset className={className} data-testid="series-scope">
      <legend className="text-sm font-semibold" style={{ color: "var(--muted)" }}>{t("seriesScopeLegend")}</legend>
      <div role="radiogroup" aria-label={t("seriesScopeLegend")} className="mt-2 flex flex-wrap gap-2">
        {options.map((option) => {
          const checked = value.scope === option.scope;
          return (
            <button
              key={option.scope}
              type="button"
              role="radio"
              aria-checked={checked}
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={checked ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
              onClick={() => onChange(option.scope === "range" ? range : { scope: option.scope } as SeriesEditScope)}
            >
              {option.label}
            </button>
          );
        })}
      </div>
      <p className="mt-2 text-xs leading-5" style={{ color: "var(--muted)" }}>{t(`seriesScopeHint_${value.scope}`)}</p>
      {value.scope === "range" ? (
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <label className="text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {t("seriesScopeFrom")}
            <DateInput className="mt-2 w-full rounded-xl px-3 py-2" value={value.from} onValueChange={(from) => onChange({ ...value, from })} />
          </label>
          <label className="text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {t("seriesScopeTo")}
            <DateInput className="mt-2 w-full rounded-xl px-3 py-2" min={value.from} value={value.to} onValueChange={(to) => onChange({ ...value, to })} />
          </label>
        </div>
      ) : null}
    </fieldset>
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

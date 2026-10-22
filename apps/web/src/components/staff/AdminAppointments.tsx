"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useMemo, useState } from "react";
import { useTranslations } from "next-intl";

import { listAdminLocations } from "@/api/facility";
import {
  bookAppointmentForClient,
  cancelAppointmentBooking,
  cancelAppointmentSlot,
  createAppointmentSlot,
  fetchAppointmentSlots,
  fetchGymStaff,
  recordAppointmentAttendance,
  type AppointmentBooking,
  type AppointmentSlot,
  type AttendanceStatus,
} from "@/api/staff";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";
import { useSession } from "@/components/session-provider";
import {
  activeBookings,
  addDays,
  appointmentRange,
  capacityOptions,
  fromDateTimeLocal,
  groupSlotsByDay,
  staffErrorMessage,
  toDateTimeLocal,
} from "@/components/staff/staff-helpers";
import {
  dangerButtonStyle,
  inputClass,
  inputStyle,
  captionClass,
  captionStyle,
  Pill,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  StaffPanel,
  StatusText,
} from "@/components/staff/staff-ui";
import { PageHeader } from "@/components/PageHeader";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatInZone, zoneLabel } from "@/lib/zoned-time";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { YourTime } from "@/components/zoned-time";
import { Select } from "@/components/ui/Select";
import { DateTimeInput } from "@/components/ui/DateInput";

type View = "week" | "day";
type Kind = AppointmentSlot["kind"];
type Format = AppointmentSlot["format"];
type Mode = NonNullable<AppointmentSlot["mode"]>;

const SLOTS_KEY = ["staff", "appointment-slots"] as const;

function nextHour(): Date {
  const date = new Date();
  date.setMinutes(0, 0, 0);
  date.setHours(date.getHours() + 1);
  return date;
}

function CreateSlotForm({
  coaches,
  locations,
  onCreated,
}: {
  coaches: Array<{ id: string; nickname: string }>;
  locations: Array<{ id: string; name: string }>;
  onCreated: () => void;
}) {
  const i18n = useUiTranslations();
  const tCoach = useTranslations("SoloCoach");
  const { tokens, currentUser } = useSession();
  const queryClient = useQueryClient();
  const baseId = useId();
  const [coachId, setCoachId] = useState("");
  // ADR-179: typed on the practice's clock, whatever the device's zone.
  const zone = useOrganizationTimeZone();
  const [startsAt, setStartsAt] = useState(() => toDateTimeLocal(nextHour(), zone));
  const [duration, setDuration] = useState("60");
  const [kind, setKind] = useState<Kind>("pt_session");
  const [format, setFormat] = useState<Format>("one_to_one");
  const [capacity, setCapacity] = useState(1);
  const [locationId, setLocationId] = useState("");
  const [notes, setNotes] = useState("");
  const [mode, setMode] = useState<Mode>("in_person");
  const [meetingUrl, setMeetingUrl] = useState("");

  const durationValue = Number(duration);
  const startsIso = fromDateTimeLocal(startsAt, zone);
  const valid =
    Boolean(startsIso) &&
    Number.isInteger(durationValue) &&
    durationValue >= 15 &&
    durationValue <= 240 &&
    (mode === "in_person" || !meetingUrl.trim() || meetingUrl.trim().startsWith("https://"));

  const mutation = useMutation({
    mutationFn: () =>
      createAppointmentSlot(tokens!.access_token, {
        coach_id: coachId || null,
        starts_at: startsIso!,
        duration_minutes: durationValue,
        kind,
        format,
        capacity,
        location_id: mode === "online" ? null : locationId || null,
        notes: notes.trim() || null,
        mode,
        meeting_url: mode === "online" ? meetingUrl.trim() || null : null,
      }),
    onSuccess: async () => {
      setNotes("");
      await queryClient.invalidateQueries({ queryKey: SLOTS_KEY });
      onCreated();
    },
  });

  const otherCoaches = coaches.filter((coach) => coach.id !== currentUser?.id);

  return (
    <form
      className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
      onSubmit={(event) => {
        event.preventDefault();
        if (valid) mutation.mutate();
      }}
    >
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-coach`} style={captionStyle}>
          {i18n("stfCoach")}
        </label>
        <Select
          id={`${baseId}-coach`}
          className={inputClass}
          onValueChange={(value) => setCoachId(value)}
          style={inputStyle}
          value={coachId}
        >
          <option value="">{i18n("stfCoachMe")}</option>
          {otherCoaches.map((coach) => (
            <option key={coach.id} value={coach.id}>
              {coach.nickname}
            </option>
          ))}
        </Select>
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-start`} style={captionStyle}>
          {i18n("stfStartsAt")}
        </label>
        <DateTimeInput
          id={`${baseId}-start`}
          className={inputClass}
          onValueChange={(value) => setStartsAt(value)}
          required
          style={inputStyle}
          value={startsAt}
        />
        {zone ? (
          <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("zonedTimeGymClock", { zone: zoneLabel(zone) })}</p>
        ) : null}
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-duration`} style={captionStyle}>
          {i18n("durationMinutesLabel")}
        </label>
        <input
          id={`${baseId}-duration`}
          className={inputClass}
          inputMode="numeric"
          max={240}
          min={15}
          onChange={(event) => setDuration(event.target.value)}
          required
          step={5}
          style={inputStyle}
          type="number"
          value={duration}
        />
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-kind`} style={captionStyle}>
          {i18n("stfKind")}
        </label>
        <Select
          id={`${baseId}-kind`}
          className={inputClass}
          onValueChange={(value) => setKind(value as Kind)}
          style={inputStyle}
          value={kind}
        >
          <option value="pt_session">{i18n("stfKindPtSession")}</option>
          <option value="assessment">{i18n("stfKindAssessment")}</option>
        </Select>
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-format`} style={captionStyle}>
          {i18n("stfFormat")}
        </label>
        <Select
          id={`${baseId}-format`}
          className={inputClass}
          onValueChange={(value) => {
            const next = value as Format;
            setFormat(next);
            setCapacity(capacityOptions(next)[0]);
          }}
          style={inputStyle}
          value={format}
        >
          <option value="one_to_one">{i18n("stfFormatOneToOne")}</option>
          <option value="semi_private">{i18n("stfFormatSemiPrivate")}</option>
        </Select>
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-capacity`} style={captionStyle}>
          {i18n("capacity45bd908")}
        </label>
        <Select
          id={`${baseId}-capacity`}
          className={inputClass}
          disabled={format === "one_to_one"}
          onValueChange={(value) => setCapacity(Number(value))}
          style={inputStyle}
          value={capacity}
        >
          {capacityOptions(format).map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </Select>
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-mode`} style={captionStyle}>
          {tCoach("slot.mode")}
        </label>
        <Select
          id={`${baseId}-mode`}
          className={inputClass}
          onValueChange={(value) => setMode(value as Mode)}
          style={inputStyle}
          value={mode}
        >
          <option value="in_person">{tCoach("box.inPerson")}</option>
          <option value="online">{tCoach("box.online")}</option>
        </Select>
      </div>
      {mode === "online" ? (
        <div className="space-y-1">
          <label className={captionClass} htmlFor={`${baseId}-meeting`} style={captionStyle}>
            {tCoach("slot.meetingUrl")}
          </label>
          <input
            id={`${baseId}-meeting`}
            className={inputClass}
            inputMode="url"
            maxLength={500}
            onChange={(event) => setMeetingUrl(event.target.value)}
            placeholder="https://"
            style={inputStyle}
            type="url"
            value={meetingUrl}
          />
        </div>
      ) : (
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-location`} style={captionStyle}>
          {i18n("stfLocation")}
        </label>
        <Select
          id={`${baseId}-location`}
          className={inputClass}
          onValueChange={(value) => setLocationId(value)}
          style={inputStyle}
          value={locationId}
        >
          <option value="">{i18n("stfNoLocation")}</option>
          {locations.map((location) => (
            <option key={location.id} value={location.id}>
              {location.name}
            </option>
          ))}
        </Select>
      </div>
      )}
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-notes`} style={captionStyle}>
          {i18n("notesOptional4d56ca9")}
        </label>
        <input
          id={`${baseId}-notes`}
          className={inputClass}
          maxLength={1000}
          onChange={(event) => setNotes(event.target.value)}
          style={inputStyle}
          value={notes}
        />
      </div>
      <div className="flex flex-wrap items-center gap-3 sm:col-span-2 lg:col-span-4">
        <button className={primaryButtonClass} disabled={!valid || mutation.isPending} style={primaryButtonStyle} type="submit">
          {mutation.isPending ? i18n("stfSaving") : i18n("stfPublishSlot")}
        </button>
        {mutation.isError ? <StatusText tone="error">{staffErrorMessage(mutation.error, i18n)}</StatusText> : null}
      </div>
    </form>
  );
}

function bookingTone(status: AppointmentBooking["status"]) {
  if (status === "attended") return "success" as const;
  if (status === "no_show") return "danger" as const;
  if (status === "cancelled") return "neutral" as const;
  return "primary" as const;
}

function SlotCard({
  slot,
  coachName,
  locationName,
  now,
  zone,
}: {
  slot: AppointmentSlot;
  coachName: string;
  locationName: string | null;
  now: number;
  zone: string | null;
}) {
  const i18n = useUiTranslations();
  const tCoach = useTranslations("SoloCoach");
  const uiLocale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const [clientId, setClientId] = useState("");
  const [showBooking, setShowBooking] = useState(false);
  const refresh = () => queryClient.invalidateQueries({ queryKey: SLOTS_KEY });

  const start = new Date(slot.starts_at);
  const end = new Date(start.getTime() + slot.duration_minutes * 60_000);
  const time = { format: (at: Date) => formatInZone(at, zone, uiLocale, { hour: "numeric", minute: "2-digit" }) };
  const bookings = slot.bookings ?? [];
  const taken = activeBookings(bookings).length;
  const cancelled = Boolean(slot.cancelled_at);
  const past = start.getTime() < now;
  const full = taken >= slot.capacity;

  const cancelSlot = useMutation({ mutationFn: () => cancelAppointmentSlot(token, slot.id), onSuccess: refresh });
  const book = useMutation({
    mutationFn: () => bookAppointmentForClient(token, slot.id, clientId),
    onSuccess: async () => {
      setClientId("");
      setShowBooking(false);
      await refresh();
    },
  });
  const attendance = useMutation({
    mutationFn: ({ id, status }: { id: string; status: AttendanceStatus }) => recordAppointmentAttendance(token, id, status),
    onSuccess: refresh,
  });
  const cancelBooking = useMutation({
    mutationFn: (id: string) => cancelAppointmentBooking(token, id),
    onSuccess: refresh,
  });
  const actionError = cancelSlot.error ?? attendance.error ?? cancelBooking.error;

  const statusLabel: Record<AppointmentBooking["status"], string> = {
    booked: i18n("stfBookingBooked"),
    attended: i18n("stfBookingAttended"),
    no_show: i18n("stfBookingNoShow"),
    cancelled: i18n("stfBookingCancelled"),
  };

  return (
    <li
      className="rounded-[1.4rem] p-4"
      style={{
        background: "var(--panel-muted)",
        border: "1px solid var(--border)",
        opacity: cancelled ? 0.7 : 1,
      }}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {time.format(start)}–{time.format(end)}
            <YourTime at={start} zone={zone} /> ·{" "}
            {slot.kind === "pt_session" ? i18n("stfKindPtSession") : i18n("stfKindAssessment")}
          </p>
          <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
            {[
              coachName,
              slot.format === "one_to_one" ? i18n("stfFormatOneToOne") : i18n("stfFormatSemiPrivate"),
              slot.mode === "online" ? tCoach("box.online") : locationName,
              i18n("stfSpotsTaken", { taken, capacity: slot.capacity }),
            ]
              .filter(Boolean)
              .join(" · ")}
          </p>
          {slot.notes ? (
            <p className="mt-1 text-xs" data-user-text style={{ color: "var(--muted)" }}>
              {slot.notes}
            </p>
          ) : null}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {cancelled ? (
            <Pill tone="neutral">{i18n("stfSlotCancelled")}</Pill>
          ) : full ? (
            <Pill tone="warning">{i18n("stfSlotFull")}</Pill>
          ) : null}
          {!cancelled && !past && !full ? (
            <button
              aria-expanded={showBooking}
              className={secondaryButtonClass}
              onClick={() => setShowBooking((value) => !value)}
              style={secondaryButtonStyle}
              type="button"
            >
              {i18n("stfBookClient")}
            </button>
          ) : null}
          {!cancelled && !past ? (
            <button
              className={secondaryButtonClass}
              disabled={cancelSlot.isPending}
              onClick={() => {
                if (window.confirm(i18n("stfCancelSlotConfirm"))) cancelSlot.mutate();
              }}
              style={dangerButtonStyle}
              type="button"
            >
              {i18n("stfCancelSlot")}
            </button>
          ) : null}
        </div>
      </div>

      {showBooking && token ? (
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <div className="min-w-60 flex-1">
            <UserSearchField label={i18n("stfClient")} onChange={(id) => setClientId(id)} token={token} value={clientId} />
          </div>
          <button
            className={primaryButtonClass}
            disabled={!clientId || book.isPending}
            onClick={() => book.mutate()}
            style={primaryButtonStyle}
            type="button"
          >
            {book.isPending ? i18n("stfBooking") : i18n("stfBook")}
          </button>
          {book.isError ? <StatusText tone="error">{staffErrorMessage(book.error, i18n)}</StatusText> : null}
        </div>
      ) : null}

      {bookings.length > 0 ? (
        <ul className="mt-3 space-y-1.5" aria-label={i18n("stfRoster")}>
          {bookings.map((booking) => (
            <li
              key={booking.id}
              className="flex flex-wrap items-center justify-between gap-2 rounded-[1rem] px-3 py-2"
              style={{ background: "var(--panel)" }}
            >
              <span className="flex flex-wrap items-center gap-2 text-sm" style={{ color: "var(--text)" }}>
                {booking.nickname ?? i18n("stfUnknownMember")}
                <Pill tone={bookingTone(booking.status)}>{statusLabel[booking.status]}</Pill>
                {booking.late_cancellation ? <Pill tone="warning">{i18n("stfLateCancellation")}</Pill> : null}
              </span>
              {booking.status === "booked" ? (
                <span className="flex flex-wrap gap-1.5">
                  <button
                    className={secondaryButtonClass}
                    disabled={attendance.isPending}
                    onClick={() => attendance.mutate({ id: booking.id, status: "attended" })}
                    style={secondaryButtonStyle}
                    type="button"
                  >
                    {i18n("stfMarkAttended")}
                  </button>
                  <button
                    className={secondaryButtonClass}
                    disabled={attendance.isPending}
                    onClick={() => attendance.mutate({ id: booking.id, status: "no_show" })}
                    style={secondaryButtonStyle}
                    title={i18n("stfNoShowHint")}
                    type="button"
                  >
                    {i18n("stfMarkNoShow")}
                  </button>
                  <button
                    className={secondaryButtonClass}
                    disabled={cancelBooking.isPending}
                    onClick={() => {
                      if (window.confirm(i18n("stfCancelBookingConfirm"))) cancelBooking.mutate(booking.id);
                    }}
                    style={dangerButtonStyle}
                    type="button"
                  >
                    {i18n("stfCancelBooking")}
                  </button>
                </span>
              ) : null}
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-3 text-xs" style={{ color: "var(--dim)" }}>
          {i18n("stfNoBookings")}
        </p>
      )}
      {actionError ? (
        <div className="mt-2">
          <StatusText tone="error">{staffErrorMessage(actionError, i18n)}</StatusText>
        </div>
      ) : null}
    </li>
  );
}

export function AdminAppointments() {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? "";
  const [view, setView] = useState<View>("week");
  const [anchor, setAnchor] = useState(() => new Date());
  const [showCreate, setShowCreate] = useState(false);
  const zone = useOrganizationTimeZone();
  const range = useMemo(() => appointmentRange(anchor, view, zone), [anchor, view, zone]);

  const slotsQuery = useQuery({
    queryKey: [...SLOTS_KEY, range.from.toISOString(), range.to.toISOString()],
    enabled: Boolean(token),
    queryFn: () => fetchAppointmentSlots(token, { from: range.from.toISOString(), to: range.to.toISOString() }),
  });
  const staffQuery = useQuery({
    queryKey: ["staff", "members"],
    enabled: Boolean(token),
    queryFn: () => fetchGymStaff(token),
    staleTime: 60_000,
  });
  const locationsQuery = useQuery({
    queryKey: ["admin", "locations"],
    enabled: Boolean(token),
    queryFn: () => listAdminLocations(token),
    staleTime: 60_000,
  });

  const coaches = (staffQuery.data ?? []).map((member) => ({
    id: member.user_id,
    nickname: member.nickname ?? i18n("stfCoach"),
  }));
  const locations = (locationsQuery.data ?? []).filter((location) => !location.archived_at);
  const coachName = (id: string) => {
    const nickname = coaches.find((coach) => coach.id === id)?.nickname;
    if (id === currentUser?.id) return nickname ? `${nickname} (${i18n("stfCoachMe")})` : i18n("stfCoachMe");
    return nickname ?? i18n("stfCoach");
  };
  const locationName = (id: string | null | undefined) =>
    id ? ((locationsQuery.data ?? []).find((location) => location.id === id)?.name ?? null) : null;

  const groups = groupSlotsByDay(slotsQuery.data ?? [], zone);
  const dayLabel = new Intl.DateTimeFormat(uiLocale, { weekday: "long", day: "numeric", month: "long" });
  // The range's bounds are moments; their days are read on the practice's clock.
  const onClock = (at: Date, options: Intl.DateTimeFormatOptions) => formatInZone(at, zone, uiLocale, options);
  const rangeLabel =
    view === "day"
      ? onClock(range.from, { weekday: "long", day: "numeric", month: "long" })
      : `${onClock(range.from, { day: "numeric", month: "short" })} – ${onClock(new Date(range.to.getTime() - 1), { day: "numeric", month: "short", year: "numeric" })}`;
  const step = view === "day" ? 1 : 7;

  return (
    <main className="min-h-screen px-4 py-10 sm:px-6 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-6">
        <PageHeader title={i18n("stfAppointmentsTitle")} />

        <StaffPanel
          labelledBy="staff-new-slot"
          title={i18n("stfNewSlot")}
          actions={
            <button
              aria-expanded={showCreate}
              className={secondaryButtonClass}
              onClick={() => setShowCreate((value) => !value)}
              style={secondaryButtonStyle}
              type="button"
            >
              {showCreate ? i18n("cancel77dfd21") : i18n("stfAddSlot")}
            </button>
          }
        >
          {showCreate ? (
            <CreateSlotForm coaches={coaches} locations={locations} onCreated={() => setShowCreate(false)} />
          ) : (
            <StatusText tone="muted">{i18n("stfNewSlotHint")}</StatusText>
          )}
        </StaffPanel>

        <StaffPanel
          labelledBy="staff-slots"
          title={rangeLabel}
          eyebrow={i18n("stfSlotsEyebrow")}
          actions={
            <>
              <div className="flex rounded-full p-0.5" role="group" style={{ background: "var(--border)" }}>
                {(["week", "day"] as const).map((option) => (
                  <button
                    key={option}
                    aria-pressed={view === option}
                    className="rounded-full px-3 py-1.5 text-xs font-semibold"
                    onClick={() => setView(option)}
                    style={view === option ? { background: "var(--text)", color: "var(--bg)" } : { color: "var(--dim)" }}
                    type="button"
                  >
                    {option === "week" ? i18n("stfWeek") : i18n("stfDay")}
                  </button>
                ))}
              </div>
              <button
                aria-label={i18n("stfPrevious")}
                className={secondaryButtonClass}
                onClick={() => setAnchor((value) => addDays(value, -step))}
                style={secondaryButtonStyle}
                type="button"
              >
                ‹
              </button>
              <button className={secondaryButtonClass} onClick={() => setAnchor(new Date())} style={secondaryButtonStyle} type="button">
                {i18n("stfToday")}
              </button>
              <button
                aria-label={i18n("stfNext")}
                className={secondaryButtonClass}
                onClick={() => setAnchor((value) => addDays(value, step))}
                style={secondaryButtonStyle}
                type="button"
              >
                ›
              </button>
            </>
          }
        >
          {slotsQuery.isPending ? (
            <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
          ) : slotsQuery.isError ? (
            <StatusText tone="error">{staffErrorMessage(slotsQuery.error, i18n)}</StatusText>
          ) : groups.length === 0 ? (
            <StatusText tone="muted">{i18n("stfNoSlots")}</StatusText>
          ) : (
            <div className="space-y-5">
              {groups.map((group) => (
                <section key={group.day} aria-label={dayLabel.format(new Date(`${group.day}T12:00:00`))}>
                  <h3 className="text-xs font-bold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
                    {dayLabel.format(new Date(`${group.day}T12:00:00`))}
                  </h3>
                  <ul className="mt-2 space-y-3">
                    {group.slots.map((slot) => (
                      <SlotCard
                        key={slot.id}
                        coachName={coachName(slot.coach_id)}
                        locationName={locationName(slot.location_id)}
                        now={slotsQuery.dataUpdatedAt}
                        slot={slot}
                        zone={zone}
                      />
                    ))}
                  </ul>
                </section>
              ))}
            </div>
          )}
        </StaffPanel>
      </div>
    </main>
  );
}

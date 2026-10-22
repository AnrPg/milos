"use client";

import { useMemo, useRef, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { apiRequest } from "@/api/client";
import type { EventScope } from "@/api/events";
import type { FacilityLocation } from "@/api/facility";
import { fetchPublicBox } from "@/api/social";
import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { SmallButton } from "@/components/community/GroupPage";
import { useSession } from "@/components/session-provider";
import { BoxPhotoUploadError, uploadBoxPhoto } from "@/lib/box-photo-upload";
import { useOrganizationTimeZoneStatus } from "@/lib/organization-slug";
import { timeZoneOptions, zoneLabel } from "@/lib/zoned-time";

import { DURATIONS, eventRequest, formProblem, type EventForm } from "./events";
import { useEventError } from "./EventParts";
import { Select } from "@/components/ui/Select";
import { DateInput, TimeInput } from "@/components/ui/DateInput";

export type EventLocation = { id: string; name: string };

/**
 * The box's locations an event can be at: the public page's when the box is
 * published, else staff's own list; none means a free address only.
 */
export function useEventLocations(slug: string | null | undefined) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: ["events", "locations", slug ?? null],
    enabled: Boolean(token && slug),
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<EventLocation[]> => {
      try {
        const page = await fetchPublicBox(slug!);
        if (page.locations.length > 0) return page.locations.map((location) => ({ id: location.id, name: location.name }));
      } catch {
        // Not published: try the staff list below.
      }
      try {
        const data = await apiRequest<{ locations: FacilityLocation[] }>(`/org/${encodeURIComponent(slug!)}/admin/locations`, { token: token! });
        return data.locations.filter((location) => !location.archived_at).map((location) => ({ id: location.id, name: location.name }));
      } catch {
        return [];
      }
    },
  });
}

/** An empty form: next Saturday at 10:00 for an hour, at the box's first location. */
export function blankEventForm(locations: EventLocation[], now: Date = new Date()): EventForm {
  const day = new Date(now);
  day.setDate(day.getDate() + ((6 - day.getDay() + 7) % 7 || 7));
  const pad = (value: number) => String(value).padStart(2, "0");
  return {
    title: "",
    description: "",
    date: [day.getFullYear(), pad(day.getMonth() + 1), pad(day.getDate())].join("-"),
    time: "10:00",
    durationMinutes: 60,
    place: locations[0] ? { kind: "location", locationId: locations[0].id } : { kind: "address", name: "", address: "" },
    capacity: "",
    paid: false,
    price: "",
    openToAll: false,
    guestPass: false,
    guestsPerMember: 1,
    goodForFriends: false,
    repeatWeekly: false,
    repeatUntil: "",
    coverMediaId: null,
    timeZone: null,
  };
}

type Body = ReturnType<typeof eventRequest>;

/**
 * «Νέο event» and editing (board 8 Q1): title, day and time, how long, where
 * (one of the box's locations or an address), how many, free or a price paid
 * at the box, members only or open to everyone, a guest pass with guests per
 * member, weekly until a date, a cover and a description. A member group's
 * event is free and for its members, so those choices don't show. Editing a
 * weekly event asks: this one, or this and the following.
 */
export function EventEditorSheet({
  title,
  eyebrow,
  initial,
  initialCoverUrl = null,
  editing = null,
  group = false,
  locations,
  clubs,
  clubId,
  onClubChange,
  coverSlug,
  gymSlug = null,
  onSubmit,
  onClose,
}: {
  title: string;
  eyebrow?: string;
  initial: EventForm;
  initialCoverUrl?: string | null;
  editing?: { seriesId: string | null } | null;
  group?: boolean;
  locations: EventLocation[];
  clubs?: { id: string; name: string }[];
  clubId?: string;
  onClubChange?: (id: string) => void;
  /** The box whose photos the cover goes to; no cover without one. */
  coverSlug?: string | null;
  /** ADR-179: the event's gym, whose clock the date and time are read on. */
  gymSlug?: string | null;
  onSubmit: (body: Body, scope: EventScope) => Promise<unknown>;
  onClose: () => void;
}) {
  const t = useTranslations("Events");
  const eventError = useEventError();
  const { tokens } = useSession();
  const fileInput = useRef<HTMLInputElement>(null);
  const [form, setForm] = useState<EventForm>(initial);
  const [scope, setScope] = useState<EventScope>("this");
  const [coverUrl, setCoverUrl] = useState<string | null>(initialCoverUrl);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [tried, setTried] = useState(false);
  const [zoneOpen, setZoneOpen] = useState(false);
  // ADR-179: the date and time are on the event's clock: its own zone when
  // it happens elsewhere, else the gym's (the device's while unknown).
  const gym = useOrganizationTimeZoneStatus(gymSlug);
  const clock = { ...form, timeZone: form.timeZone ?? gym.zone };
  const zones = useMemo(() => timeZoneOptions(clock.timeZone, gym.zone), [clock.timeZone, gym.zone]);
  const away = Boolean(gym.zone && clock.timeZone && clock.timeZone !== gym.zone);
  const problem = formProblem(clock, new Date(), { editing: Boolean(editing) });
  const save = useMutation({
    mutationFn: () => onSubmit(eventRequest(clock, { group, editing: Boolean(editing), gymTimeZone: gym.zone }), scope),
    onSuccess: onClose,
  });
  const set = <K extends keyof EventForm>(key: K, value: EventForm[K]) => setForm((current) => ({ ...current, [key]: value }));
  const formId = editing ? "event-edit-form" : "event-create-form";

  async function pick(file: File | undefined) {
    if (!file || !coverSlug || !tokens?.access_token) return;
    setUploading(true);
    setUploadError(null);
    try {
      const media = await uploadBoxPhoto(tokens.access_token, file, coverSlug);
      set("coverMediaId", media.id);
      setCoverUrl(media.url ?? null);
    } catch (caught) {
      setUploadError(caught instanceof BoxPhotoUploadError ? t(["upload", caught.reason].join("_")) : eventError(caught));
    } finally {
      setUploading(false);
    }
  }

  const durationLabel = (minutes: number) =>
    minutes % 60 === 0 ? t("hours", { count: minutes / 60 }) : minutes > 60 ? t("hoursMinutes", { hours: Math.floor(minutes / 60), minutes: minutes % 60 }) : t("minutes", { count: minutes });
  const durations = DURATIONS.includes(form.durationMinutes) ? DURATIONS : [...DURATIONS, form.durationMinutes].sort((a, b) => a - b);

  return (
    <Sheet
      labelId={formId}
      eyebrow={eyebrow}
      title={title}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary type="submit" form={[formId, "body"].join("-")} disabled={save.isPending || uploading}>
            {editing ? t("save") : t("publish")}
          </SheetButton>
        </>
      }
    >
      <form
        id={[formId, "body"].join("-")}
        noValidate
        className="flex flex-col gap-4"
        onSubmit={(event) => {
          event.preventDefault();
          setTried(true);
          if (!problem) save.mutate();
        }}
      >
        {clubs && clubs.length > 1 && onClubChange ? (
          <Field label={t("fieldClub")}>
            <Select value={clubId} onValueChange={(value) => onClubChange(value)} className="min-h-11 rounded-2xl px-3 text-sm font-normal" style={inputStyle}>
              {clubs.map((club) => (
                <option key={club.id} value={club.id}>{club.name}</option>
              ))}
            </Select>
          </Field>
        ) : null}
        <Field label={t("fieldTitle")}>
          <input
            value={form.title}
            maxLength={120}
            required
            aria-invalid={tried && problem === "title"}
            onChange={(event) => set("title", event.target.value)}
            placeholder={t("fieldTitlePlaceholder")}
            className="min-h-11 rounded-2xl px-3 text-sm font-normal"
            style={inputStyle}
          />
        </Field>
        <div className="grid grid-cols-2 gap-2">
          <Field label={t("fieldDate")}>
            <DateInput value={form.date} onValueChange={(value) => set("date", value)} className="min-h-11 rounded-2xl px-3 text-sm font-normal" style={inputStyle} />
          </Field>
          <Field label={t("fieldTime")}>
            <TimeInput value={form.time} onValueChange={(value) => set("time", value)} className="min-h-11 rounded-2xl px-3 text-sm font-normal" style={inputStyle} />
          </Field>
        </div>
        {clock.timeZone ? (
          <div className="-mt-2 flex flex-col gap-2 text-xs" style={{ color: "var(--dim)" }}>
            <p className="flex flex-wrap items-center gap-x-2">
              <span>{t(away ? "zoneAway" : "zoneGym", { zone: zoneLabel(clock.timeZone) })}</span>
              {!zoneOpen ? (
                <button type="button" className="font-semibold underline" style={{ color: "var(--primary)" }} onClick={() => setZoneOpen(true)}>
                  {t("zoneChange")}
                </button>
              ) : null}
            </p>
            {!gym.confirmed && gym.zone ? (
              <p role="status" className="rounded-xl px-3 py-2" style={{ background: "color-mix(in srgb, var(--warning) 12%, transparent)", color: "var(--text)" }}>
                {t("zoneGymUnconfirmed", { zone: zoneLabel(gym.zone) })}
              </p>
            ) : null}
            {form.place.kind === "address" && !away && !zoneOpen ? <p>{t("zoneAwayHint")}</p> : null}
            {zoneOpen ? (
              <Field label={t("fieldTimeZone")}>
                <Select
                  value={clock.timeZone}
                  onValueChange={(value) => set("timeZone", value)}
                  className="min-h-11 rounded-2xl px-3 text-sm font-normal"
                  style={inputStyle}
                >
                  {zones.map((zone) => (
                    <option key={zone} value={zone}>
                      {zone === gym.zone ? t("zoneGymOption", { zone }) : zone}
                    </option>
                  ))}
                </Select>
              </Field>
            ) : null}
          </div>
        ) : null}
        <Field label={t("fieldDuration")}>
          <Select
            value={form.durationMinutes}
            onValueChange={(value) => set("durationMinutes", Number(value))}
            className="min-h-11 rounded-2xl px-3 text-sm font-normal"
            style={inputStyle}
          >
            {durations.map((minutes) => (
              <option key={minutes} value={minutes}>{durationLabel(minutes)}</option>
            ))}
          </Select>
        </Field>

        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldPlace")}</legend>
          <div role="radiogroup" aria-label={t("fieldPlace")} className="flex flex-wrap gap-2">
            {locations.map((location) => (
              <ChoicePill
                key={location.id}
                selected={form.place.kind === "location" && form.place.locationId === location.id}
                onSelect={() => set("place", { kind: "location", locationId: location.id })}
              >
                {location.name}
              </ChoicePill>
            ))}
            <ChoicePill
              selected={form.place.kind === "address"}
              onSelect={() => set("place", form.place.kind === "address" ? form.place : { kind: "address", name: "", address: "" })}
            >
              {t("placeElsewhere")}
            </ChoicePill>
          </div>
          {form.place.kind === "address" ? (
            <div className="flex flex-col gap-2">
              <Field label={t("fieldPlaceName")}>
                <input
                  value={form.place.name}
                  maxLength={120}
                  onChange={(event) => set("place", { kind: "address", name: event.target.value, address: form.place.kind === "address" ? form.place.address : "" })}
                  placeholder={t("fieldPlaceNamePlaceholder")}
                  className="min-h-11 rounded-2xl px-3 text-sm font-normal"
                  style={inputStyle}
                />
              </Field>
              <Field label={t("fieldAddress")}>
                <input
                  value={form.place.address}
                  maxLength={200}
                  onChange={(event) => set("place", { kind: "address", name: form.place.kind === "address" ? form.place.name : "", address: event.target.value })}
                  placeholder={t("fieldAddressPlaceholder")}
                  className="min-h-11 rounded-2xl px-3 text-sm font-normal"
                  style={inputStyle}
                />
              </Field>
            </div>
          ) : null}
        </fieldset>

        <Field label={t("fieldCapacity")}>
          <input
            inputMode="numeric"
            value={form.capacity}
            onChange={(event) => set("capacity", event.target.value.replace(/\D/g, "").slice(0, 5))}
            placeholder={t("fieldCapacityPlaceholder")}
            className="min-h-11 rounded-2xl px-3 text-sm font-normal"
            style={inputStyle}
          />
        </Field>

        {group ? (
          <p className="rounded-2xl px-3 py-2 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>{t("groupTerms")}</p>
        ) : (
          <>
            <fieldset className="flex flex-col gap-2">
              <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldPrice")}</legend>
              <div role="radiogroup" aria-label={t("fieldPrice")} className="flex gap-2">
                <ChoicePill selected={!form.paid} onSelect={() => set("paid", false)}>{t("free")}</ChoicePill>
                <ChoicePill selected={form.paid} onSelect={() => set("paid", true)} hint={t("paidHint")}>{t("paid")}</ChoicePill>
              </div>
              {form.paid ? (
                <Field label={t("fieldAmount")}>
                  <input
                    inputMode="decimal"
                    value={form.price}
                    aria-invalid={tried && problem === "price"}
                    onChange={(event) => set("price", event.target.value.replace(/[^\d.,]/g, "").slice(0, 8))}
                    placeholder="15"
                    className="min-h-11 rounded-2xl px-3 text-sm font-normal"
                    style={inputStyle}
                  />
                </Field>
              ) : null}
            </fieldset>
            <fieldset className="flex flex-col gap-2">
              <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldWho")}</legend>
              <div role="radiogroup" aria-label={t("fieldWho")} className="flex gap-2">
                <ChoicePill selected={!form.openToAll} onSelect={() => set("openToAll", false)} hint={t("membersOnlyHint")}>{t("membersOnly")}</ChoicePill>
                <ChoicePill selected={form.openToAll} onSelect={() => set("openToAll", true)} hint={t("openToAllHint")}>{t("openToAll")}</ChoicePill>
              </div>
            </fieldset>
            <div className="flex flex-col gap-2">
              <label className="flex min-h-11 items-center gap-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
                <input type="checkbox" checked={form.guestPass} onChange={(event) => set("guestPass", event.target.checked)} className="h-5 w-5" />
                {t("fieldGuestPass")}
              </label>
              {form.guestPass ? (
                <Field label={t("fieldGuestsPerMember")}>
                  <Select
                    value={form.guestsPerMember}
                    onValueChange={(value) => set("guestsPerMember", Number(value))}
                    className="min-h-11 rounded-2xl px-3 text-sm font-normal"
                    style={inputStyle}
                  >
                    {[1, 2, 3, 4, 5].map((count) => (
                      <option key={count} value={count}>{t("guestsCount", { count })}</option>
                    ))}
                  </Select>
                </Field>
              ) : null}
            </div>
            {form.openToAll || form.guestPass ? (
              <label className="flex min-h-11 items-center gap-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
                <input type="checkbox" checked={form.goodForFriends} onChange={(event) => set("goodForFriends", event.target.checked)} className="h-5 w-5" />
                <span>
                  {t("fieldGoodForFriends")}
                  <span className="block text-xs font-normal" style={{ color: "var(--dim)" }}>{t("goodForFriendsHint")}</span>
                </span>
              </label>
            ) : null}
          </>
        )}

        {editing ? null : (
          <div className="flex flex-col gap-2">
            <label className="flex min-h-11 items-center gap-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
              <input type="checkbox" checked={form.repeatWeekly} onChange={(event) => set("repeatWeekly", event.target.checked)} className="h-5 w-5" />
              {t("fieldRepeat")}
            </label>
            {form.repeatWeekly ? (
              <Field label={t("fieldRepeatUntil")}>
                <DateInput
                  value={form.repeatUntil}
                  min={form.date}
                  aria-invalid={tried && problem === "repeat"}
                  onValueChange={(value) => set("repeatUntil", value)}
                  className="min-h-11 rounded-2xl px-3 text-sm font-normal"
                  style={inputStyle}
                />
              </Field>
            ) : null}
          </div>
        )}

        {coverSlug ? (
          <div className="flex flex-col gap-2">
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldCover")}</p>
            {coverUrl ? (
              // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
              <img src={coverUrl} alt="" className="aspect-[16/6] w-full rounded-2xl object-cover" />
            ) : null}
            <div className="flex gap-2">
              <SmallButton disabled={uploading} onClick={() => fileInput.current?.click()}>
                {uploading ? t("uploading") : coverUrl ? t("coverChange") : t("coverAdd")}
              </SmallButton>
              {form.coverMediaId ? (
                <SmallButton
                  onClick={() => {
                    set("coverMediaId", null);
                    setCoverUrl(null);
                  }}
                >
                  {t("coverRemove")}
                </SmallButton>
              ) : null}
            </div>
            <input ref={fileInput} type="file" accept="image/*" className="sr-only" aria-label={t("coverAdd")} onChange={(event) => void pick(event.target.files?.[0])} />
            <ErrorLine message={uploadError} />
          </div>
        ) : null}

        <Field label={t("fieldDescription")}>
          <textarea
            value={form.description}
            maxLength={2000}
            rows={3}
            onChange={(event) => set("description", event.target.value)}
            placeholder={t("fieldDescriptionPlaceholder")}
            className="rounded-2xl px-3 py-2 text-sm font-normal"
            style={inputStyle}
          />
        </Field>

        {editing?.seriesId ? <ScopePicker value={scope} onChange={setScope} /> : null}
        <ErrorLine message={tried && problem ? t(["problem", problem].join("_")) : null} />
        <ErrorLine message={eventError(save.error)} />
      </form>
    </Sheet>
  );
}

/** A weekly event's change: this one, or this and the following weeks. */
export function ScopePicker({ value, onChange }: { value: EventScope; onChange: (value: EventScope) => void }) {
  const t = useTranslations("Events");
  return (
    <fieldset className="flex flex-col gap-1">
      <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("scopeLabel")}</legend>
      <div role="radiogroup" aria-label={t("scopeLabel")} className="flex gap-2">
        <ChoicePill selected={value === "this"} onSelect={() => onChange("this")}>{t("scopeThis")}</ChoicePill>
        <ChoicePill selected={value === "following"} onSelect={() => onChange("following")}>{t("scopeFollowing")}</ChoicePill>
      </div>
    </fieldset>
  );
}

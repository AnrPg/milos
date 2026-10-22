"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { CLASS_LEVELS } from "@/api/schedule";
import { fetchBoxSchedule, type PublicBoxPage, type PublicBoxSchedule } from "@/api/social";
import { WeekStrip, weekStart } from "@/components/member-app/box/schedule/WeekStrip";
import { formatLocalIsoDate, parseLocalDate } from "@/components/schedule/calendar-window";
import { TrialSheet } from "@/components/trials/TrialSheet";
import type { TrialOffer } from "@/api/trials";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import { CollapsibleFilterBar } from "@/components/filters/CollapsibleFilterBar";

type Slot = PublicBoxSchedule["slots"][number];
const ALL = "";

/**
 * Πρόγραμμα for visitors (plan §5a board 4 Q7): the members' week strip and
 * compact rows with a chip row for class type, level and audience, and a
 * class sheet without booking or package dimming. Members of the gym get a
 * link to their own Πρόγραμμα, where they book. Classes that take trial
 * guests carry a «Δοκιμαστικό» tag and a chip filter, and their sheet opens
 * the trial sheet with the class picked (board 6 Q2).
 */
export function VisitorSchedule({ page, token, member }: { page: PublicBoxPage; token: string; member: boolean }) {
  const t = useTranslations("BoxPage");
  const tSchedule = useTranslations("BoxSchedule");
  const tTrials = useTranslations("Trials");
  const locale = useLocale();
  const [selectedDate, setSelectedDate] = useState(() => formatLocalIsoDate(new Date()));
  const [type, setType] = useState(ALL);
  const [level, setLevel] = useState(ALL);
  const [audience, setAudience] = useState(ALL);
  const [open, setOpen] = useState<Slot | null>(null);
  const [trialOnly, setTrialOnly] = useState(false);
  const [trialSlot, setTrialSlot] = useState<Slot | null>(null);
  const monday = weekStart(selectedDate);

  const schedule = useQuery({
    queryKey: ["social", "box-schedule", page.box.slug, monday],
    queryFn: () => {
      const start = parseLocalDate(monday);
      const end = new Date(start);
      end.setDate(end.getDate() + 7);
      return fetchBoxSchedule(token, page.box.slug, { startAt: start.toISOString(), endAt: end.toISOString() });
    },
  });

  const slots = useMemo(() => schedule.data?.slots ?? [], [schedule.data]);
  const offer = (schedule.data?.trial_offer ?? null) as TrialOffer | null;
  const canAsk = Boolean(offer && !offer.blocked_reason && !offer.mine);
  const takesTrials = (slot: Slot) => canAsk && (slot.trial_seats ?? 0) > 0;
  const types = useMemo(
    () => [...new Map(slots.filter((slot) => slot.class_type).map((slot) => [slot.class_type!.id, slot.class_type!.name])).entries()],
    [slots],
  );
  const audiences = useMemo(() => [...new Set(slots.flatMap((slot) => slot.class_type?.audiences ?? []))], [slots]);
  const levels = CLASS_LEVELS.filter((value) => slots.some((slot) => slot.class_type?.level === value));
  const day = slots
    .filter((slot) => formatLocalIsoDate(new Date(slot.scheduled_at)) === selectedDate)
    .filter((slot) => !type || slot.class_type?.id === type)
    .filter((slot) => !level || slot.class_type?.level === level)
    .filter((slot) => !audience || (slot.class_type?.audiences ?? []).includes(audience))
    .filter((slot) => !trialOnly || takesTrials(slot))
    .sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at));
  const locationName = (id: string | null | undefined) =>
    page.locations.length > 1 ? (page.locations.find((location) => location.id === id)?.name ?? null) : null;

  return (
    <div className="flex flex-col gap-3">
      <WeekStrip selectedDate={selectedDate} onSelect={setSelectedDate} />
      <CollapsibleFilterBar
        ariaLabel={tSchedule("filtersAria")}
        activeCount={[type, level, audience].filter((value) => value !== ALL).length + (trialOnly ? 1 : 0)}
        onClear={() => {
          setType(ALL);
          setLevel(ALL);
          setAudience(ALL);
          setTrialOnly(false);
        }}
      >
        <div className="flex flex-wrap gap-2">
          <Chip label={tSchedule("chipType")} value={type} onChange={setType} options={types.map(([id, name]) => ({ value: id, label: name }))} />
          <Chip
            label={tSchedule("chipLevel")}
            value={level}
            onChange={setLevel}
            options={levels.map((value) => ({ value, label: tSchedule(`level_${value}`) }))}
          />
          <Chip
            label={tSchedule("audience")}
            value={audience}
            onChange={setAudience}
            options={audiences.map((value) => ({ value, label: audienceLabel(tSchedule, value) }))}
          />
          {canAsk && slots.some(takesTrials) ? (
            <button
              type="button"
              aria-pressed={trialOnly}
              onClick={() => setTrialOnly((value) => !value)}
              className="flex min-h-10 shrink-0 items-center rounded-full px-3.5 text-sm font-semibold"
              style={
                trialOnly
                  ? { background: "var(--text)", color: "var(--bg)" }
                  : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }
              }
            >
              {tTrials("chipTrial")}
            </button>
          ) : null}
        </div>
      </CollapsibleFilterBar>

      {schedule.isPending ? <p className="py-6 text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {schedule.isError ? (
        <p className="py-6 text-center text-sm" style={{ color: "var(--dim)" }}>
          {tSchedule("loadFailed")}{" "}
          <button type="button" onClick={() => void schedule.refetch()} className="font-bold underline">
            {tSchedule("retry")}
          </button>
        </p>
      ) : null}
      {schedule.isSuccess && day.length === 0 ? (
        <p className="rounded-2xl p-5 text-center text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          {tSchedule("emptyDay")}
        </p>
      ) : null}
      <ul className="flex flex-col gap-2">
        {day.map((slot) => (
          <li key={slot.id}>
            <Row slot={slot} locale={locale} location={locationName(slot.location_id)} trial={takesTrials(slot)} onOpen={() => setOpen(slot)} />
          </li>
        ))}
      </ul>
      {open ? (
        <VisitorClassSheet
          slot={open}
          location={page.locations.find((location) => location.id === open.location_id)?.name ?? null}
          memberHref={member ? `/org/${page.box.slug}/box/schedule?open_slot=${open.id}` : null}
          onTrial={takesTrials(open) && new Date(open.scheduled_at) > new Date() ? () => (setTrialSlot(open), setOpen(null)) : null}
          onClose={() => setOpen(null)}
        />
      ) : null}
      {trialSlot && offer ? (
        <TrialSheet page={page} token={token} offer={offer} initialSlot={trialSlot} onClose={() => setTrialSlot(null)} />
      ) : null}
    </div>
  );
}

function audienceLabel(t: ReturnType<typeof useTranslations<"BoxSchedule">>, value: string) {
  return t.has(`audience_${value}`) ? t(`audience_${value}` as never) : value;
}

function Chip({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (value: string) => void;
}) {
  const t = useTranslations("BoxSchedule");
  if (options.length === 0) return null;
  const active = value !== ALL;
  return (
    <label
      className="relative flex min-h-10 shrink-0 items-center rounded-full ps-3.5 pe-8 text-sm font-semibold"
      style={
        active
          ? { background: "var(--text)", color: "var(--bg)" }
          : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }
      }
    >
      <span>{active ? options.find((option) => option.value === value)?.label : label}</span>
      <span aria-hidden="true" className="pointer-events-none absolute end-3 text-xs">▾</span>
      <select
        aria-label={label}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="absolute inset-0 cursor-pointer opacity-0"
      >
        <option value={ALL}>{t("optionAll")}</option>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  );
}

function Row({
  slot,
  locale,
  location,
  trial,
  onOpen,
}: {
  slot: Slot;
  locale: string;
  location: string | null;
  trial: boolean;
  onOpen: () => void;
}) {
  const t = useTranslations("BoxSchedule");
  const tTrials = useTranslations("Trials");
  const time = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(slot.scheduled_at));
  const detail = [slot.coach?.nickname, location].filter(Boolean).join(" · ");
  const past = new Date(slot.scheduled_at) < new Date();
  return (
    <button
      type="button"
      onClick={onOpen}
      className="grid min-h-16 w-full grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl px-4 py-3 text-start"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", opacity: past ? 0.55 : 1 }}
    >
      <span className="flex flex-col items-start">
        <span className="font-mono text-sm font-bold" style={{ color: "var(--text-soft)" }}>{time}</span>
        {slot.duration_minutes ? (
          <span className="text-[11px]" style={{ color: "var(--dim)" }}>{t("minutes", { count: slot.duration_minutes })}</span>
        ) : null}
      </span>
      <span className="flex min-w-0 flex-col">
        <span className="flex min-w-0 items-center gap-2">
          <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{slot.name}</span>
          {trial && !past ? (
            <span className="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold" style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--success)" }}>
              {tTrials("tag")}
            </span>
          ) : null}
        </span>
        {detail ? <span className="truncate text-xs" style={{ color: "var(--dim)" }}>{detail}</span> : null}
      </span>
      <span className="text-xs font-bold" style={{ color: past ? "var(--dim)" : slot.spots_remaining === 0 ? "var(--dim)" : "var(--success)" }}>
        {past ? t("statusPast") : slot.spots_remaining === 0 ? t("statusFull") : slot.spots_remaining != null ? t("spotsLeft", { count: slot.spots_remaining }) : null}
      </span>
    </button>
  );
}

function VisitorClassSheet({
  slot,
  location,
  memberHref,
  onTrial,
  onClose,
}: {
  slot: Slot;
  location: string | null;
  memberHref: string | null;
  onTrial: (() => void) | null;
  onClose: () => void;
}) {
  const t = useTranslations("BoxPage");
  const tTrials = useTranslations("Trials");
  const tSchedule = useTranslations("BoxSchedule");
  const locale = useLocale();
  const dialog = useModalFocusTrap<HTMLElement>(onClose);
  const start = new Date(slot.scheduled_at);
  const when = new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long" }).format(start);
  const clock = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(start);
  const level = slot.class_type?.level;
  const facts = [
    slot.coach?.nickname ? [tSchedule("coach"), slot.coach.nickname] : null,
    level ? [tSchedule("chipLevel"), tSchedule(`level_${level}` as never)] : null,
    slot.class_type && slot.class_type.audiences.length > 0
      ? [tSchedule("audience"), slot.class_type.audiences.map((value) => audienceLabel(tSchedule, value)).join(", ")]
      : null,
    location ? [tSchedule("location"), location] : null,
    slot.spots_remaining != null ? [t("spots"), slot.spots_remaining === 0 ? tSchedule("statusFull") : tSchedule("spotsLeft", { count: slot.spots_remaining })] : null,
  ].filter(Boolean) as [string, string][];

  return (
    <div className="fixed inset-0 z-[60] flex items-end justify-center" style={{ background: "var(--scrim)" }} onClick={onClose} role="presentation">
      <section
        ref={dialog}
        role="dialog"
        aria-modal="true"
        aria-labelledby="visitor-class-title"
        onClick={(event) => event.stopPropagation()}
        className="flex max-h-[90dvh] w-full max-w-xl flex-col rounded-t-3xl"
        style={{ background: "var(--panel)", borderTop: "1px solid var(--border)" }}
      >
        <div className="flex justify-center pt-2.5">
          <span aria-hidden="true" className="h-1 w-10 rounded-full" style={{ background: "var(--border)" }} />
        </div>
        <div className="flex-1 overflow-y-auto px-5 pb-4 pt-2">
          <h2 id="visitor-class-title" className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{slot.name}</h2>
          <p className="mt-1 text-sm font-semibold first-letter:uppercase" style={{ color: "var(--text-soft)" }}>
            {when} · {clock}
            {slot.duration_minutes ? ` · ${tSchedule("minutes", { count: slot.duration_minutes })}` : ""}
          </p>
          <dl className="mt-4 grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
            {facts.map(([term, value]) => (
              <div key={term} className="contents">
                <dt style={{ color: "var(--dim)" }}>{term}</dt>
                <dd style={{ color: "var(--text)" }}>{value}</dd>
              </div>
            ))}
          </dl>
        </div>
        <footer className="flex flex-col gap-2 px-5 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3" style={{ borderTop: "1px solid var(--border)" }}>
          {memberHref ? (
            <Link href={memberHref} className="flex min-h-12 items-center justify-center rounded-2xl text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {t("bookAsMember")}
            </Link>
          ) : onTrial ? (
            <button type="button" onClick={onTrial} className="flex min-h-12 items-center justify-center rounded-2xl text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {tTrials("bookWithTrial")}
            </button>
          ) : null}
          <button type="button" onClick={onClose} className="min-h-11 rounded-2xl text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("close")}
          </button>
        </footer>
      </section>
    </div>
  );
}

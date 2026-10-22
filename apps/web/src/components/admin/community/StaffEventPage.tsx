"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import {
  cancelStaffEvent,
  fetchStaffEvent,
  markPaid,
  messageAttendees,
  PAYMENT_METHODS,
  removeAttendee,
  sendTrialOffer,
  setCheckedIn,
  staffEventKey,
  updateStaffEvent,
  type PaymentMethod,
  type StaffAttendee,
  type StaffEvent,
} from "@/api/admin-events";
import { Badge } from "@/components/community/MembersTab";
import { MoreMenu } from "@/components/community/PostCard";
import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { EventEditorSheet, useEventLocations } from "@/components/events/EventEditorSheet";
import { CancelEventSheet } from "@/components/events/EventPage";
import { useEventError, usePriceLabel } from "@/components/events/EventParts";
import { formFromEvent, formatWhen, hasEnded, placeName } from "@/components/events/events";
import { invalidateEvents } from "@/components/events/use-events";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref } from "@/lib/organization-slug";
import { can } from "@/lib/role-navigation";

type ListTab = "going" | "waitlisted" | "cancelled" | "came";
const LIST_TABS: ListTab[] = ["going", "waitlisted", "cancelled", "came"];

/**
 * An event for staff (board 8 Q6): Πάνε · Αναμονή · Ακύρωσαν · Ήρθαν with
 * «Ήρθε», «Πλήρωσε» and freeing a place, late cancels marked with the
 * person's last 90 days, «Μήνυμα σε όλους», edit and cancel (this one or the
 * following weeks), the numbers, and after the event the one trial offer to
 * people who came and aren't members.
 */
export function StaffEventPage({ eventId }: { eventId: string }) {
  const t = useTranslations("EventsAdmin");
  const tEvents = useTranslations("Events");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const { selectedOrganizationSlug } = useSelectedMembershipRole();
  const event = useQuery({ queryKey: staffEventKey(eventId), enabled: Boolean(token), queryFn: () => fetchStaffEvent(token, eventId) });
  const back = adminHref("/admin/community?tab=events", selectedOrganizationSlug);

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-3xl flex-col gap-5 pb-28">
        <Link href={back} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>‹ {t("backToEvents")}</Link>
        {event.isPending ? (
          <p style={{ color: "var(--dim)" }}>{tEvents("loading")}</p>
        ) : event.data ? (
          <StaffEventView event={event.data} />
        ) : (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{tEvents("eventNotFound")}</p>
        )}
      </div>
    </main>
  );
}

/** Runs a staff action and puts the event it returns in place. */
function useStaffAction(eventId: string) {
  const queryClient = useQueryClient();
  return async (fresh: StaffEvent) => {
    queryClient.setQueryData(staffEventKey(eventId), fresh);
    await invalidateEvents(queryClient);
  };
}

function Panel({ title, children }: { title?: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      {title ? <h2 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{title}</h2> : null}
      {children}
    </section>
  );
}

function StaffEventView({ event }: { event: StaffEvent }) {
  const t = useTranslations("EventsAdmin");
  const tEvents = useTranslations("Events");
  const locale = useLocale();
  const price = usePriceLabel();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const { membership } = useSelectedMembershipRole();
  const manage = can(membership, "manage_events");
  const applied = useStaffAction(event.id);
  const locations = useEventLocations(manage ? event.box.slug : null);
  const [tab, setTab] = useState<ListTab>("going");
  const [sheet, setSheet] = useState<"edit" | "cancel" | "message" | "trial" | null>(null);
  const over = hasEnded(event);
  const lists: Record<ListTab, StaffAttendee[]> = {
    going: event.attendees.going,
    waitlisted: event.attendees.waitlisted,
    cancelled: event.attendees.cancelled,
    came: event.attendees.going.filter((row) => row.checked_in_at),
  };
  const { stats } = event;
  const numbers: [string, number][] = [
    [t("numGoing"), stats.going],
    [t("numCame"), stats.came],
    [t("numNoShows"), stats.no_shows],
    [t("numLateCancels"), stats.late_cancels],
    [t("numWaitlisted"), stats.waitlisted],
    [t("numGuests"), stats.guests],
    ...(event.price_cents > 0 ? ([[t("numPaid"), stats.paid]] as [string, number][]) : []),
    [t("numTrialRequests"), stats.trial_requests],
    [t("numJoined"), stats.converted],
  ];

  return (
    <>
      <header className="flex flex-col gap-1">
        <p className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
          {[event.club.name, event.group?.name].filter(Boolean).join(" › ")}
        </p>
        <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)", textDecoration: event.cancelled ? "line-through" : undefined }}>{event.title}</h1>
        <p className="text-sm first-letter:uppercase" style={{ color: "var(--text-soft)" }}>
          {[formatWhen(event.starts_at, event.ends_at, locale, event.time_zone), placeName(event.place), price(event)].filter(Boolean).join(" · ")}
        </p>
        {event.cancelled ? (
          <p role="status" className="mt-2 rounded-2xl px-4 py-3 text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--danger) 14%, var(--panel))", color: "var(--text)" }}>
            {event.cancel_reason ? tEvents("cancelledWithReason", { reason: event.cancel_reason }) : tEvents("cancelledNotice")}
          </p>
        ) : null}
      </header>

      <div className="flex flex-wrap gap-2">
        {manage && !event.cancelled ? (
          <>
            <SheetButton primary onClick={() => setSheet("message")}>{t("messageAll")}</SheetButton>
            <SheetButton onClick={() => setSheet("edit")}>{tEvents("edit")}</SheetButton>
            <SheetButton onClick={() => setSheet("cancel")}>{tEvents("cancelEvent")}</SheetButton>
          </>
        ) : null}
        <Link
          href={`/events/${event.id}`}
          className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {t("openEventPage")}
        </Link>
      </div>

      <Panel title={t("numbersTitle")}>
        <dl className="grid grid-cols-3 gap-2 sm:grid-cols-5">
          {numbers.map(([label, value]) => (
            <div key={label} className="flex flex-col rounded-2xl px-3 py-2" style={{ background: "var(--panel-raised)" }}>
              <dd className="font-mono text-xl font-extrabold tabular-nums" style={{ color: "var(--text)" }}>{value}</dd>
              <dt className="text-xs" style={{ color: "var(--text-soft)" }}>{label}</dt>
            </div>
          ))}
        </dl>
      </Panel>

      {over && !event.cancelled && manage ? (
        <Panel title={t("trialTitle")}>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {event.trial_offer.sent_at
              ? t("trialSent", { date: new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(event.trial_offer.sent_at)) })
              : t("trialHint")}
          </p>
          <SheetButton
            primary
            disabled={Boolean(event.trial_offer.sent_at) || !event.trial_offer.can_send || event.trial_offer.recipients === 0}
            onClick={() => setSheet("trial")}
          >
            {t("trialSend", { count: event.trial_offer.recipients })}
          </SheetButton>
        </Panel>
      ) : null}

      <div role="tablist" aria-label={t("attendeesAria")} className="flex gap-2 overflow-x-auto">
        {LIST_TABS.map((value) => (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={tab === value}
            onClick={() => setTab(value)}
            className="min-h-11 flex-1 shrink-0 whitespace-nowrap rounded-2xl px-3 text-sm font-semibold"
            style={{
              background: tab === value ? "var(--primary)" : "var(--panel)",
              color: tab === value ? "var(--primary-contrast)" : "var(--text)",
              border: "1px solid var(--border)",
            }}
          >
            {t(["tab", value].join("_"), { count: lists[value].length })}
          </button>
        ))}
      </div>
      <Panel>
        {lists[tab].length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(["empty", tab].join("_"))}</p>
        ) : (
          <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
            {lists[tab].map((row) => (
              <AttendeeRow key={row.person.id} event={event} row={row} />
            ))}
          </ul>
        )}
      </Panel>

      {sheet === "edit" ? (
        <EventEditorSheet
          title={tEvents("edit")}
          eyebrow={event.title}
          initial={formFromEvent(event)}
          initialCoverUrl={event.cover_url ?? null}
          editing={{ seriesId: event.series_id ?? null }}
          group={Boolean(event.channel_id)}
          locations={locations.data ?? []}
          coverSlug={can(membership, "manage_settings") ? event.box.slug : null}
          gymSlug={event.box.slug}
          onSubmit={async (body, scope) => applied(await updateStaffEvent(token, event.id, { ...body, scope }))}
          onClose={() => setSheet(null)}
        />
      ) : null}
      {sheet === "cancel" ? (
        <CancelEventSheet
          event={event}
          onCancel={async (reason, scope) => applied(await cancelStaffEvent(token, event.id, reason, scope))}
          onClose={() => setSheet(null)}
        />
      ) : null}
      {sheet === "message" ? <MessageSheet event={event} onClose={() => setSheet(null)} /> : null}
      {sheet === "trial" ? <TrialOfferSheet event={event} onClose={() => setSheet(null)} /> : null}
    </>
  );
}

function AttendeeRow({ event, row }: { event: StaffEvent; row: StaffAttendee }) {
  const t = useTranslations("EventsAdmin");
  const locale = useLocale();
  const eventError = useEventError();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const { membership, selectedOrganizationSlug } = useSelectedMembershipRole();
  const applied = useStaffAction(event.id);
  const [sheet, setSheet] = useState<"paid" | "remove" | null>(null);
  const userId = row.person.id;
  const act = useMutation({
    mutationFn: async (action: "check_in" | "undo_check_in" | "remove") => {
      const fresh =
        action === "remove" ? await removeAttendee(token, event.id, userId) : await setCheckedIn(token, event.id, userId, action === "check_in");
      await applied(fresh);
    },
    onSuccess: () => setSheet(null),
  });
  const manage = can(membership, "manage_events");
  const checkIn = manage || can(membership, "check_in");
  const takePayments = manage || can(membership, "take_payments");
  const holds = row.status === "going";
  const clock = (iso: string) =>
    new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
  const notes = [
    row.source === "guest" ? t("guestOf", { name: row.invited_by?.nickname ?? "?" }) : null,
    row.paid_at ? t("paidWith", { method: t(["pay", row.payment_method ?? "other"].join("_")) }) : null,
    row.removed_by ? t("removedBy", { name: row.removed_by.nickname ?? "?" }) : null,
    row.status === "cancelled" && !row.late_cancel && !row.removed_by && row.cancelled_at ? t("cancelledAt", { time: clock(row.cancelled_at) }) : null,
    row.late_cancels_90d > 0 ? t("lateCancels90", { count: row.late_cancels_90d }) : null,
  ].filter(Boolean);

  return (
    <li className="flex flex-col gap-1 py-3">
      <div className="flex flex-wrap items-center gap-3">
        <Link href={adminHref(`/admin/users/${userId}`, selectedOrganizationSlug)} className="flex min-w-0 grow items-center gap-3">
          <PersonAvatar name={row.person.nickname} url={row.person.avatar_url} />
          <span className="min-w-0">
            <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{row.person.nickname ?? "?"}</span>
            {notes.length > 0 ? <span className="block text-xs" style={{ color: "var(--dim)" }}>{notes.join(" · ")}</span> : null}
          </span>
        </Link>
        {row.late_cancel && row.cancelled_at ? (
          <span className="shrink-0 rounded-full px-2.5 py-1 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--warning) 18%, transparent)", color: "var(--warning)" }}>
            {t("lateCancelTag", { time: clock(row.cancelled_at) })}
          </span>
        ) : null}
        <Badge muted={!row.member}>{row.member ? t("member") : t("notMember")}</Badge>
        {holds && event.price_cents > 0 && !row.paid_at ? <Badge muted>{t("unpaid")}</Badge> : null}
        {holds && checkIn && !event.cancelled ? (
          <button
            type="button"
            aria-pressed={Boolean(row.checked_in_at)}
            disabled={act.isPending}
            onClick={() => act.mutate(row.checked_in_at ? "undo_check_in" : "check_in")}
            className="min-h-11 shrink-0 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
            style={{
              background: row.checked_in_at ? "var(--primary)" : "var(--panel-raised)",
              color: row.checked_in_at ? "var(--primary-contrast)" : "var(--text)",
              border: row.checked_in_at ? "none" : "1px solid var(--border)",
            }}
          >
            {t("cameToggle")}
          </button>
        ) : null}
        {holds && takePayments && event.price_cents > 0 && !row.paid_at ? (
          <button
            type="button"
            onClick={() => setSheet("paid")}
            className="min-h-11 shrink-0 rounded-full px-4 text-sm font-semibold"
            style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
          >
            {t("markPaid")}
          </button>
        ) : null}
        {manage && row.status !== "cancelled" && !event.cancelled ? (
          <MoreMenu label={t("personActions", { name: row.person.nickname ?? "?" })} items={[{ label: t("remove"), onSelect: () => setSheet("remove") }]} />
        ) : null}
      </div>
      <ErrorLine message={eventError(act.error)} />
      {sheet === "paid" ? <PaidSheet event={event} row={row} onClose={() => setSheet(null)} /> : null}
      {sheet === "remove" ? (
        <Sheet
          labelId={["remove", userId].join("-")}
          eyebrow={event.title}
          title={t("removeTitle", { name: row.person.nickname ?? "?" })}
          onClose={() => setSheet(null)}
          footer={
            <>
              <SheetButton onClick={() => setSheet(null)}>{t("keep")}</SheetButton>
              <SheetButton primary disabled={act.isPending} onClick={() => act.mutate("remove")}>{t("remove")}</SheetButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("removeBody")}</p>
          <ErrorLine message={eventError(act.error)} />
        </Sheet>
      ) : null}
    </li>
  );
}

/** «Πλήρωσε»: how they paid at the box (a Finance receipt when they have a record there). */
function PaidSheet({ event, row, onClose }: { event: StaffEvent; row: StaffAttendee; onClose: () => void }) {
  const t = useTranslations("EventsAdmin");
  const price = usePriceLabel();
  const eventError = useEventError();
  const { tokens } = useSession();
  const applied = useStaffAction(event.id);
  const [method, setMethod] = useState<PaymentMethod>("cash");
  const pay = useMutation({
    mutationFn: async () => applied(await markPaid(tokens!.access_token, event.id, row.person.id, method)),
    onSuccess: onClose,
  });
  return (
    <Sheet
      labelId={["paid", row.person.id].join("-")}
      eyebrow={[row.person.nickname ?? "?", price(event)].join(" · ")}
      title={t("markPaidTitle")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("keep")}</SheetButton>
          <SheetButton primary disabled={pay.isPending} onClick={() => pay.mutate()}>{t("markPaid")}</SheetButton>
        </>
      }
    >
      <fieldset className="flex flex-col gap-2">
        <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("paymentMethod")}</legend>
        <div role="radiogroup" aria-label={t("paymentMethod")} className="grid grid-cols-2 gap-2">
          {PAYMENT_METHODS.map((value) => (
            <ChoicePill key={value} selected={method === value} onSelect={() => setMethod(value)}>
              {t(["pay", value].join("_"))}
            </ChoicePill>
          ))}
        </div>
      </fieldset>
      <ErrorLine message={eventError(pay.error)} />
    </Sheet>
  );
}

/** «Μήνυμα σε όλους»: a notification to everyone going. */
function MessageSheet({ event, onClose }: { event: StaffEvent; onClose: () => void }) {
  const t = useTranslations("EventsAdmin");
  const eventError = useEventError();
  const { tokens } = useSession();
  const [body, setBody] = useState("");
  const send = useMutation({ mutationFn: () => messageAttendees(tokens!.access_token, event.id, body.trim()) });
  return (
    <Sheet
      labelId={["message", event.id].join("-")}
      eyebrow={event.title}
      title={send.isSuccess ? t("messageSentTitle") : t("messageAll")}
      onClose={onClose}
      footer={
        send.isSuccess ? (
          <SheetButton primary onClick={onClose}>{t("ok")}</SheetButton>
        ) : (
          <>
            <SheetButton onClick={onClose}>{t("keep")}</SheetButton>
            <SheetButton primary disabled={!body.trim() || send.isPending} onClick={() => send.mutate()}>{t("send")}</SheetButton>
          </>
        )
      }
    >
      {send.isSuccess ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("messageSent", { count: send.data })}</p>
      ) : (
        <div className="flex flex-col gap-3">
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("messageHint", { count: event.going_count })}</p>
          <Field label={t("messageLabel")}>
            <textarea value={body} maxLength={1000} rows={4} onChange={(change) => setBody(change.target.value)} className="rounded-2xl px-3 py-2 text-sm font-normal" style={inputStyle} />
          </Field>
          <ErrorLine message={eventError(send.error)} />
        </div>
      )}
    </Sheet>
  );
}

/** The one trial offer after the event, to people who came and aren't members. */
function TrialOfferSheet({ event, onClose }: { event: StaffEvent; onClose: () => void }) {
  const t = useTranslations("EventsAdmin");
  const eventError = useEventError();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const send = useMutation({
    mutationFn: () => sendTrialOffer(tokens!.access_token, event.id),
    onSuccess: () => invalidateEvents(queryClient),
  });
  return (
    <Sheet
      labelId={["trial-offer", event.id].join("-")}
      eyebrow={event.title}
      title={send.isSuccess ? t("trialSentTitle") : t("trialTitle")}
      onClose={onClose}
      footer={
        send.isSuccess ? (
          <SheetButton primary onClick={onClose}>{t("ok")}</SheetButton>
        ) : (
          <>
            <SheetButton onClick={onClose}>{t("keep")}</SheetButton>
            <SheetButton primary disabled={send.isPending} onClick={() => send.mutate()}>{t("trialSend", { count: event.trial_offer.recipients })}</SheetButton>
          </>
        )
      }
    >
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {send.isSuccess ? t("trialSentBody", { count: send.data }) : t("trialConfirm", { count: event.trial_offer.recipients })}
      </p>
      <ErrorLine message={eventError(send.error)} />
    </Sheet>
  );
}

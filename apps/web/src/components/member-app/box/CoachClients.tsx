"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { adminRecordAttendance } from "@/api/admin";
import { fetchCoachingRelationships } from "@/api/roles";
import {
  fetchAppointmentSlots,
  fetchFormReviewQueue,
  fetchReplyQueue,
  recordAppointmentAttendance,
  type FormReview,
  type ReplyQueueItem,
} from "@/api/staff";
import { AvatarChips, CountBadge } from "@/components/admin/DashboardWidgets";
import { HubCard } from "@/components/member-app/HubParts";
import type { BoxExtensionProps } from "@/components/member-app/box/box-extensions";
import { useBoxSchedule } from "@/components/member-app/box/BoxToday";
import {
  checkedInCount,
  coachesHere,
  todaysDesk,
  type DeskPerson,
  type DeskSession,
} from "@/components/member-app/box/coach-clients";
import { useSession } from "@/components/session-provider";
import { FORM_REVIEWS_KEY, ReviewForm } from "@/components/staff/FormReviewQueue";
import { chatThreadHref, replyUrgency, sortReplyQueue } from "@/components/staff/staff-helpers";
import { Pill } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug, useOrganizationTimeZone } from "@/lib/organization-slug";
import { can } from "@/lib/role-navigation";
import { SPARK_GO_STYLE } from "@/lib/spark";
import { addDaysToKey, dateKeyInZone, formatInZone, startOfDayInZone } from "@/lib/zoned-time";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** Rows a queue shows before it points to the console for the rest. */
const QUEUE_ROWS = 5;
const CLIENT_CHIPS = 6;

// Shared with the console's staff home, so work done in either refreshes both.
const REPLY_QUEUE_KEY = ["staff", "reply-queue"] as const;
const RELATIONSHIPS_KEY = ["staff", "coaching-relationships"] as const;
const DESK_APPOINTMENTS_KEY = ["staff", "desk", "appointments"] as const;

const rowClass = "flex min-h-12 w-full items-center justify-between gap-3 py-2.5 text-start";
/** Rows are divided by a line; the first has none. */
const rowStyle = (index: number) => (index === 0 ? undefined : { borderTop: "1px solid var(--border)" });

/**
 * Box › «Πελάτες μου» (ADR-198, vision §6.2 and §7.10): the coach's own work
 * in the member app, for whoever coaches at the selected provider (a solo
 * coach is owner and coach). It is a Box extension, so neither layout knows
 * about it. Each part keeps one home elsewhere: a reply opens the thread, a
 * form review answers through the console's own form, a client opens their
 * console profile, attendance writes to the same endpoints the console uses.
 */
export function CoachClientsBoxExtension({ membership }: BoxExtensionProps) {
  if (!coachesHere(membership)) return null;
  return <CoachClients membership={membership} />;
}

function CoachClients({ membership }: Pick<BoxExtensionProps, "membership">) {
  const t = useTranslations("CoachClients");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const coachId = currentUser?.id ?? null;
  const zone = useOrganizationTimeZone();
  const now = useMemo(() => new Date(), []);
  const today = dateKeyInZone(now, zone);
  const coaching = can(membership, "manage_coaching");
  const runsClasses = can(membership, "run_classes");
  const runsSessions = can(membership, "manage_appointments");

  const replies = useQuery({
    queryKey: REPLY_QUEUE_KEY,
    enabled: Boolean(token) && coaching,
    queryFn: () => fetchReplyQueue(token!),
    refetchInterval: 60_000,
  });
  const reviews = useQuery({
    queryKey: [...FORM_REVIEWS_KEY, "submitted"],
    enabled: Boolean(token) && coaching,
    queryFn: () => fetchFormReviewQueue(token!, "submitted"),
  });
  const clients = useQuery({
    queryKey: [...RELATIONSHIPS_KEY, { coach: coachId }],
    enabled: Boolean(token && coachId),
    queryFn: () => fetchCoachingRelationships(token!, { coachUserId: coachId! }),
  });
  // The member's Box already loads this week's schedule; the desk reads the same query.
  const schedule = useBoxSchedule(token, now);
  const appointments = useQuery({
    queryKey: [...DESK_APPOINTMENTS_KEY, coachId, today],
    enabled: Boolean(token && coachId) && runsSessions,
    queryFn: () =>
      fetchAppointmentSlots(token!, {
        from: startOfDayInZone(today, zone).toISOString(),
        to: startOfDayInZone(addDaysToKey(today, 1), zone).toISOString(),
        coach_id: coachId!,
      }),
  });

  const replyItems = sortReplyQueue(replies.data ?? []);
  const reviewItems = reviews.data ?? [];
  const clientItems = clients.data ?? [];
  const desk = todaysDesk(runsClasses ? (schedule.data?.slots ?? []) : [], appointments.data ?? [], coachId, zone, now);

  // A part with nothing in it is hidden, and so is the section (vision §4.2).
  if (replyItems.length + reviewItems.length + clientItems.length + desk.length === 0) return null;

  return (
    <section aria-labelledby="box-coach-clients" data-testid="box-coach-clients" className="flex flex-col gap-3">
      <h2 id="box-coach-clients" className="px-1 text-lg font-bold" style={{ color: "var(--text)" }}>
        {t("title")}
      </h2>
      {replyItems.length > 0 ? <ReplyPart items={replyItems} /> : null}
      {reviewItems.length > 0 ? <ReviewPart items={reviewItems} /> : null}
      {desk.length > 0 ? <DeskPart sessions={desk} /> : null}
      {clientItems.length > 0 ? (
        <ClientsPart people={clientItems.map((item) => ({ id: item.client_user_id, name: item.client_nickname ?? t("unknownClient") }))} />
      ) : null}
    </section>
  );
}

function PartHeader({ title, count }: { title: string; count: number }) {
  return (
    <span className="flex items-center gap-2">
      <span>{title}</span>
      <CountBadge value={count} tone="primary" />
    </span>
  );
}

/** «Περιμένουν απάντηση»: each row opens the thread where the coach answers. */
function ReplyPart({ items }: { items: ReplyQueueItem[] }) {
  const t = useTranslations("CoachClients");
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const slug = useOrganizationSlug();
  const now = new Date();

  return (
    <HubCard>
      <h3 className="mb-1 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        <PartHeader title={t("replies")} count={items.length} />
      </h3>
      <ul>
        {items.slice(0, QUEUE_ROWS).map((item, index) => {
          const urgency = replyUrgency(item, now);
          return (
            <li key={item.message_id}>
              <Link href={chatThreadHref(item.thread_id)} className={rowClass} style={rowStyle(index)}>
                <span className="flex min-w-0 flex-col">
                  <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {item.client_nickname ?? t("unknownClient")}
                  </span>
                  <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
                    {t("sentAt", { time: formatInZone(item.sent_at, zone, locale, "day-time") })}
                  </span>
                </span>
                <span className="flex shrink-0 items-center gap-2">
                  {urgency === "overdue" ? <Pill tone="danger">{t("overdue")}</Pill> : null}
                  {urgency === "due_soon" ? <Pill tone="warning">{t("dueSoon")}</Pill> : null}
                  <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
      {items.length > QUEUE_ROWS ? <MoreInConsole href={adminHref("/admin", slug)} /> : null}
    </HubCard>
  );
}

/** «Αξιολόγηση τεχνικής»: a row opens the video and the console's feedback form in a sheet. */
function ReviewPart({ items }: { items: FormReview[] }) {
  const t = useTranslations("CoachClients");
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const slug = useOrganizationSlug();
  const [openId, setOpenId] = useState<string | null>(null);
  const open = items.find((review) => review.id === openId) ?? null;

  return (
    <HubCard>
      <h3 className="mb-1 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        <PartHeader title={t("reviews")} count={items.length} />
      </h3>
      <ul>
        {items.slice(0, QUEUE_ROWS).map((review, index) => (
          <li key={review.id}>
            <button type="button" className={rowClass} style={rowStyle(index)} onClick={() => setOpenId(review.id)}>
              <span className="flex min-w-0 flex-col">
                <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {review.nickname ?? t("unknownClient")}
                  {review.exercise_name ? <span style={{ color: "var(--dim)" }}> · {review.exercise_name}</span> : null}
                </span>
                <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
                  {t("sentAt", { time: formatInZone(review.inserted_at, zone, locale, "day-time") })}
                </span>
              </span>
              <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
            </button>
          </li>
        ))}
      </ul>
      {items.length > QUEUE_ROWS ? <MoreInConsole href={adminHref("/admin", slug)} /> : null}
      {open ? (
        <Dialog onClose={() => setOpenId(null)} title={open.nickname ?? t("unknownClient")} eyebrow={open.exercise_name ?? t("reviews")} size="md">
          <div className="flex flex-col gap-3">
            <a
              href={open.video_url}
              target="_blank"
              rel="noopener noreferrer"
              className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold"
              style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("openVideo")}
            </a>
            {open.note ? (
              <p className="whitespace-pre-wrap break-words text-sm leading-6" data-user-text style={{ color: "var(--text-soft)" }}>
                {open.note}
              </p>
            ) : null}
            <ReviewForm review={open} onDone={() => setOpenId(null)} />
          </div>
        </Dialog>
      ) : null}
    </HubCard>
  );
}

/** «Check-in σήμερα»: today's classes and sessions the coach runs; a row opens its roster. */
function DeskPart({ sessions }: { sessions: DeskSession[] }) {
  const t = useTranslations("CoachClients");
  const tCoach = useTranslations("SoloCoach");
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const [openId, setOpenId] = useState<string | null>(null);
  const open = sessions.find((session) => session.id === openId) ?? null;
  const titleOf = (session: DeskSession) => session.title ?? tCoach("box.ptSession");

  return (
    <HubCard>
      <h3 className="mb-1 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {t("desk")}
      </h3>
      <ul>
        {sessions.map((session, index) => (
          <li key={session.id}>
            <button type="button" className={rowClass} style={rowStyle(index)} onClick={() => setOpenId(session.id)}>
              <span className="w-12 shrink-0 text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>
                {formatInZone(session.startsAt, zone, locale, "time")}
              </span>
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{titleOf(session)}</span>
                <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
                  {t("checkedIn", { count: checkedInCount(session), total: session.roster.length })}
                </span>
              </span>
              <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
            </button>
          </li>
        ))}
      </ul>
      {open ? (
        <Dialog
          onClose={() => setOpenId(null)}
          title={titleOf(open)}
          eyebrow={formatInZone(open.startsAt, zone, locale, "time")}
          description={t("checkedIn", { count: checkedInCount(open), total: open.roster.length })}
          size="md"
        >
          <ul className="flex flex-col">
            {open.roster.map((person, index) => (
              <RosterRow key={person.bookingId} session={open} person={person} index={index} />
            ))}
          </ul>
        </Dialog>
      ) : null}
    </HubCard>
  );
}

/** One person on the roster: «Ήρθε» checks them in, «Δεν ήρθε» records a no-show. */
function RosterRow({ session, person, index }: { session: DeskSession; person: DeskPerson; index: number }) {
  const t = useTranslations("CoachClients");
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const mark = useMutation({
    mutationFn: async (status: "attended" | "no_show") => {
      if (session.kind === "class") await adminRecordAttendance(tokens!.access_token, session.slotId, person.userId, { status });
      else await recordAppointmentAttendance(tokens!.access_token, person.bookingId, status);
    },
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["box", "schedule"] }),
        queryClient.invalidateQueries({ queryKey: DESK_APPOINTMENTS_KEY }),
      ]);
    },
  });
  const name = person.name ?? t("unknownClient");

  return (
    <li className="flex flex-wrap items-center justify-between gap-2 py-3" style={rowStyle(index)}>
      <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{name}</span>
      <span role="group" aria-label={t("attendanceOf", { name })} className="flex shrink-0 gap-2">
        <AttendanceButton
          pressed={person.attendance === "attended"}
          busy={mark.isPending}
          onClick={() => mark.mutate("attended")}
          go
        >
          {t("attended")}
        </AttendanceButton>
        <AttendanceButton pressed={person.attendance === "no_show"} busy={mark.isPending} onClick={() => mark.mutate("no_show")}>
          {t("noShow")}
        </AttendanceButton>
      </span>
      {mark.isError ? (
        <ErrorNotice variant="field" className="w-full">{t("markError")}</ErrorNotice>
      ) : null}
    </li>
  );
}

function AttendanceButton({
  pressed,
  busy,
  onClick,
  go,
  children,
}: {
  pressed: boolean;
  busy: boolean;
  onClick: () => void;
  /** «Ήρθε» is the go-now action (Spark) until it is done. */
  go?: boolean;
  children: string;
}) {
  const style = pressed
    ? { background: "var(--text)", color: "var(--bg)", border: "1px solid var(--text)" }
    : go
      ? { ...SPARK_GO_STYLE, border: "1px solid transparent" }
      : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" };
  return (
    <button
      type="button"
      aria-pressed={pressed}
      disabled={busy || pressed}
      onClick={onClick}
      className="min-h-9 rounded-full px-3 text-xs font-bold disabled:cursor-default"
      style={style}
    >
      {pressed ? `✓ ${children}` : children}
    </button>
  );
}

/** «Πελάτες»: the coach's own clients; a chip opens the client's console profile. */
function ClientsPart({ people }: { people: Array<{ id: string; name: string }> }) {
  const t = useTranslations("CoachClients");
  const slug = useOrganizationSlug();
  const [showAll, setShowAll] = useState(false);
  const visible = showAll ? people : people.slice(0, CLIENT_CHIPS);

  return (
    <HubCard>
      <h3 className="mb-2 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        <PartHeader title={t("clients")} count={people.length} />
      </h3>
      <AvatarChips people={visible.map((person) => ({ ...person, href: adminHref(`/admin/users/${person.id}`, slug) }))} />
      {people.length > CLIENT_CHIPS ? (
        <button
          type="button"
          aria-expanded={showAll}
          onClick={() => setShowAll((value) => !value)}
          className="mt-2 min-h-11 w-full rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {showAll ? t("showFewer") : t("showAll", { count: people.length })}
        </button>
      ) : null}
    </HubCard>
  );
}

function MoreInConsole({ href }: { href: string }) {
  const t = useTranslations("CoachClients");
  return (
    <Link href={href} className="mt-2 block text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
      {t("moreInConsole")}
    </Link>
  );
}

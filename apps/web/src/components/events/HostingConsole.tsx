"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import {
  answerCohostRequest,
  cohostRequestsKey,
  eventAnalyticsKey,
  eventFinancesKey,
  fetchCohostRequests,
  fetchEventAnalytics,
  fetchEventFinances,
  fetchStaffEvents,
  sendCohostTrialOffer,
  staffEventsKey,
  type CohostRequest,
  type ConsoleScope,
  type StaffEventRow,
} from "@/api/admin-events";
import type { EventHostChoice, EventListScope } from "@/api/events";
import { HostedEventPanel, type EventConsoleScope } from "@/components/admin/community/StaffEventPage";
import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { Select } from "@/components/ui/Select";

import { DateBlock, useEventError, useGoingLabel, usePriceLabel } from "./EventParts";
import { formatPrice, formatWhen } from "./events";
import { HostedEventSheet, useEventHosts } from "./HostedEventSheet";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { guideAnchor } from "@/lib/guides/anchors";
import { GuideButton } from "@/components/guides/GuideButton";
import { BackButton, BackLink } from "@/components/ui/BackLink";

type Tab = "manage" | "finances" | "analytics";
const TABS: Tab[] = ["manage", "finances", "analytics"];
const LIST_SCOPES: EventListScope[] = ["upcoming", "past"];
const NUMBER_SCOPES: ConsoleScope[] = ["all", "upcoming", "past"];

/**
 * The organiser console (ADR-185 §5): for each host the person runs events
 * as («Ως εγώ» once they have hosted, and each business), three tabs and
 * nothing else from the gym's admin. Διαχείριση: the events, each with its
 * attendees, check-in, messages and co-hosts, and a business's co-host
 * requests. Οικονομικά: income, refunds and what is still owed, per event and
 * in total. Αναλυτικά: views, RSVPs, waitlist, attendance and conversion.
 */
export function HostingConsole({ org = null, tab = null, event = null }: { org?: string | null; tab?: string | null; event?: string | null }) {
  const t = useTranslations("EventsHosting");
  const tEvents = useTranslations("Events");
  const hosts = useEventHosts();
  const consoles = (hosts.data ?? []).filter((host): host is EventHostChoice & { organization_id: string } => Boolean(host.organization_id && host.slug));
  const [orgId, setOrgId] = useState<string | null>(org);
  const host = consoles.find((entry) => entry.organization_id === orgId) ?? consoles[0];
  const [current, setCurrent] = useState<Tab>(tab === "finances" || tab === "analytics" ? tab : "manage");
  const [creating, setCreating] = useState(false);

  return (
    <HubPage
      title={t("title")}
      actions={
        <div className="flex shrink-0 items-center gap-2">
          <GuideButton guide="events_organising" className="min-h-11 rounded-full px-3 text-sm font-semibold" />
          <button {...guideAnchor("events.new")} type="button" onClick={() => setCreating(true)} className="min-h-11 shrink-0 rounded-full px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {tEvents("newEvent")}
          </button>
        </div>
      }
    >
      <BackLink href="/events" className="text-sm font-semibold" style={{ color: "var(--dim)" }}>{t("backToEvents")}</BackLink>
      {hosts.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{tEvents("loading")}</p>
      ) : !host ? (
        <HubCard>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("empty")}</p>
        </HubCard>
      ) : (
        <>
          {consoles.length > 1 ? (
            <Field label={tEvents("hostAs")}>
              <Select value={host.organization_id} onValueChange={(value) => setOrgId(String(value))} className="min-h-11 rounded-2xl px-3 text-sm font-normal" style={inputStyle}>
                {consoles.map((entry) => (
                  <option key={entry.organization_id} value={entry.organization_id}>
                    {entry.kind === "self" ? tEvents("hostSelf") : (entry.name ?? entry.slug)}
                  </option>
                ))}
              </Select>
            </Field>
          ) : null}
          <SegmentPicker guide="events.tabs" ariaLabel={t("tabsAria")} variant="track" stretch value={current} onChange={setCurrent} options={TABS.map((value) => ({ value, label: t(`tab_${value}`) }))} />
          {current === "manage" ? (
            <ManageTab key={host.organization_id} host={host} initialEvent={host.organization_id === org ? event : null} />
          ) : current === "finances" ? (
            <FinancesTab key={host.organization_id} slug={host.slug!} />
          ) : (
            <AnalyticsTab key={host.organization_id} slug={host.slug!} />
          )}
        </>
      )}
      {creating ? <HostedEventSheet initialHost={host?.id ?? null} onClose={() => setCreating(false)} /> : null}
    </HubPage>
  );
}

function consoleScope(host: EventHostChoice): EventConsoleScope {
  return { slug: host.slug ?? null, manage: true, checkIn: true, takePayments: true, settings: false, peopleLinks: false };
}

function ManageTab({ host, initialEvent }: { host: EventHostChoice; initialEvent: string | null }) {
  const t = useTranslations("EventsHosting");
  const tEvents = useTranslations("Events");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = host.slug ?? null;
  const [scope, setScope] = useState<EventListScope>("upcoming");
  const [selected, setSelected] = useState<string | null>(initialEvent);
  const events = useQuery({ queryKey: staffEventsKey(scope, slug), enabled: Boolean(token), queryFn: () => fetchStaffEvents(token, scope, slug) });

  if (selected) {
    return (
      <>
        <BackButton type="button" onClick={() => setSelected(null)} className="self-start text-sm font-semibold" style={{ color: "var(--dim)" }}>{t("allEvents")}</BackButton>
        <HostedEventPanel eventId={selected} scope={consoleScope(host)} />
      </>
    );
  }

  return (
    <>
      <SegmentPicker ariaLabel={tEvents("scopeAria")} stretch value={scope} onChange={setScope} options={LIST_SCOPES.map((value) => ({ value, label: tEvents(value) }))} />
      <HubCard guide="events.list">
        {events.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{tEvents("loading")}</p>
        ) : (events.data ?? []).length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{scope === "upcoming" ? t("emptyUpcoming") : t("emptyPast")}</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {(events.data ?? []).map((row) => (
              <ConsoleEventItem key={row.id} event={row} onOpen={() => setSelected(row.id)} />
            ))}
          </ul>
        )}
      </HubCard>
      {host.kind === "business" ? <CohostRequests slug={slug} /> : null}
    </>
  );
}

function ConsoleEventItem({ event, onOpen }: { event: StaffEventRow; onOpen: () => void }) {
  const tEvents = useTranslations("Events");
  const t = useTranslations("EventsHosting");
  const locale = useLocale();
  const price = usePriceLabel();
  const going = useGoingLabel();
  return (
    <li>
      <button type="button" onClick={onOpen} className="flex w-full items-center gap-3 rounded-2xl px-3 py-3 text-start" style={{ background: "var(--panel-raised)" }}>
        <DateBlock iso={event.starts_at} timeZone={event.time_zone} />
        <span className="min-w-0 grow">
          <span className="block truncate font-bold" style={{ color: "var(--text)", textDecoration: event.cancelled ? "line-through" : undefined }}>{event.title}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
            {[formatWhen(event.starts_at, event.ends_at, locale, event.time_zone), price(event)].join(" · ")}
          </span>
          <span className="block text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
            {event.cancelled
              ? tEvents("pillCancelled")
              : [going(event), (event.cohosts ?? []).length ? t("cohostCount", { count: (event.cohosts ?? []).length }) : null].filter(Boolean).join(" · ")}
          </span>
        </span>
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
      </button>
    </li>
  );
}

/** A business's side of co-hosting: requests to answer, events it co-hosts, and its own trial offer after one. */
function CohostRequests({ slug }: { slug: string | null }) {
  const t = useTranslations("EventsHosting");
  const tEvents = useTranslations("Events");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const errorText = useEventError();
  const [problem, setProblem] = useState<string | null>(null);
  const [sent, setSent] = useState<string | null>(null);
  const requests = useQuery({ queryKey: cohostRequestsKey(slug), enabled: Boolean(token), queryFn: () => fetchCohostRequests(token, slug) });
  const answer = useMutation({
    mutationFn: ({ id, value }: { id: string; value: "accepted" | "declined" | "removed" }) => answerCohostRequest(token, id, value, slug),
    onSuccess: (rows) => {
      setProblem(null);
      queryClient.setQueryData(cohostRequestsKey(slug), rows);
    },
    onError: (error) => setProblem(errorText(error)),
  });
  const offer = useMutation({
    mutationFn: (id: string) => sendCohostTrialOffer(token, id, slug),
    onSuccess: async (count) => {
      setProblem(null);
      setSent(t("trialSent", { count }));
      await queryClient.invalidateQueries({ queryKey: cohostRequestsKey(slug) });
    },
    onError: (error) => setProblem(errorText(error)),
  });
  const rows = requests.data ?? [];

  return (
    <HubCard eyebrow={t("requestsTitle")}>
      {rows.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{requests.isPending ? tEvents("loading") : t("requestsEmpty")}</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {rows.map((row) => (
            <CohostRequestItem
              key={row.id}
              row={row}
              locale={locale}
              busy={answer.isPending || offer.isPending}
              onAnswer={(value) => answer.mutate({ id: row.id, value })}
              onTrialOffer={() => offer.mutate(row.id)}
            />
          ))}
        </ul>
      )}
      {problem ? <ErrorNotice className="mt-2">{problem}</ErrorNotice> : null}
      {sent ? <p role="status" className="mt-2 text-sm" style={{ color: "var(--text-soft)" }}>{sent}</p> : null}
    </HubCard>
  );
}

function CohostRequestItem({
  row,
  locale,
  busy,
  onAnswer,
  onTrialOffer,
}: {
  row: CohostRequest;
  locale: string;
  busy: boolean;
  onAnswer: (value: "accepted" | "declined" | "removed") => void;
  onTrialOffer: () => void;
}) {
  const t = useTranslations("EventsHosting");
  const button = "min-h-10 rounded-full px-3 text-sm font-semibold disabled:opacity-60";
  return (
    <li className="flex flex-col gap-2 rounded-2xl px-3 py-3" style={{ background: "var(--panel-raised)" }}>
      <span className="font-bold" style={{ color: "var(--text)" }}>{row.event.title}</span>
      <span className="text-xs" style={{ color: "var(--dim)" }}>
        {[formatWhen(row.event.starts_at, row.event.ends_at, locale, row.event.time_zone), t("requestFrom", { host: row.host.name ?? row.host.slug ?? "?" }), row.event.weekly ? t("weekly") : null]
          .filter(Boolean)
          .join(" · ")}
      </span>
      <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t(`status_${row.status}`)}</span>
      <div className="flex flex-wrap gap-2">
        {row.status === "pending" && row.answerable ? (
          <>
            <button type="button" disabled={busy} onClick={() => onAnswer("accepted")} className={button} style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {t("accept")}
            </button>
            <button type="button" disabled={busy} onClick={() => onAnswer("declined")} className={button} style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
              {t("decline")}
            </button>
          </>
        ) : null}
        {row.status === "accepted" && row.answerable ? (
          <button type="button" disabled={busy} onClick={() => onAnswer("removed")} className={button} style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("withdraw")}
          </button>
        ) : null}
        {row.can_send_trial_offer ? (
          <button type="button" disabled={busy} onClick={onTrialOffer} className={button} style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("sendTrialOffer")}
          </button>
        ) : row.trial_offer_sent_at ? (
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("trialOfferSent")}</span>
        ) : null}
      </div>
    </li>
  );
}

function ScopePicker({ value, onChange }: { value: ConsoleScope; onChange: (value: ConsoleScope) => void }) {
  const t = useTranslations("EventsHosting");
  return <SegmentPicker ariaLabel={t("scopeAria")} semantics="radiogroup" stretch value={value} onChange={onChange} options={NUMBER_SCOPES.map((scope) => ({ value: scope, label: t(`scope_${scope}`) }))} />;
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col rounded-2xl px-3 py-2" style={{ background: "var(--panel-raised)" }}>
      <span className="text-xs" style={{ color: "var(--dim)" }}>{label}</span>
      <span className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{value}</span>
    </div>
  );
}

function FinancesTab({ slug }: { slug: string }) {
  const t = useTranslations("EventsHosting");
  const tEvents = useTranslations("Events");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [scope, setScope] = useState<ConsoleScope>("all");
  const finances = useQuery({ queryKey: eventFinancesKey(slug, scope), enabled: Boolean(token), queryFn: () => fetchEventFinances(token, scope, slug) });
  const amount = (cents: number, currency: string) =>
    formatPrice(cents, currency, locale) ?? new Intl.NumberFormat(locale, { style: "currency", currency: currency || "EUR", minimumFractionDigits: 0 }).format(0);
  const rows = (finances.data?.events ?? []).filter((row) => row.price_cents > 0 || row.paid_count > 0 || row.refunded_count > 0);

  return (
    <div {...guideAnchor("events.finances")} className="flex flex-col gap-4">
      <ScopePicker value={scope} onChange={setScope} />
      {finances.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{tEvents("loading")}</p>
      ) : (
        <>
          {(finances.data?.totals ?? []).map((total) => (
            <HubCard key={total.currency} eyebrow={t("totals", { currency: total.currency })}>
              <div className="grid grid-cols-2 gap-2">
                <Stat label={t("income")} value={amount(total.paid_cents, total.currency)} />
                <Stat label={t("refunds")} value={amount(total.refunded_cents, total.currency)} />
                <Stat label={t("net")} value={amount(total.net_cents, total.currency)} />
                <Stat label={t("outstanding")} value={amount(total.outstanding_cents, total.currency)} />
              </div>
            </HubCard>
          ))}
          <HubCard eyebrow={t("perEvent")}>
            {rows.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("financesEmpty")}</p>
            ) : (
              <ul className="flex flex-col gap-2">
                {rows.map((row) => (
                  <li key={row.event_id} className="flex flex-col gap-1 rounded-2xl px-3 py-3" style={{ background: "var(--panel-raised)" }}>
                    <span className="font-bold" style={{ color: "var(--text)", textDecoration: row.cancelled_at ? "line-through" : undefined }}>{row.title}</span>
                    <span className="text-xs" style={{ color: "var(--dim)" }}>{formatWhen(row.starts_at, row.ends_at ?? row.starts_at, locale, row.time_zone)}</span>
                    <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
                      {[
                        t("paidLine", { count: row.paid_count, amount: amount(row.paid_cents, row.currency) }),
                        row.refunded_count ? t("refundedLine", { count: row.refunded_count, amount: amount(row.refunded_cents, row.currency) }) : null,
                        row.outstanding_count ? t("outstandingLine", { count: row.outstanding_count, amount: amount(row.outstanding_cents, row.currency) }) : null,
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </HubCard>
        </>
      )}
    </div>
  );
}

function AnalyticsTab({ slug }: { slug: string }) {
  const t = useTranslations("EventsHosting");
  const tEvents = useTranslations("Events");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [scope, setScope] = useState<ConsoleScope>("all");
  const analytics = useQuery({ queryKey: eventAnalyticsKey(slug, scope), enabled: Boolean(token), queryFn: () => fetchEventAnalytics(token, scope, slug) });
  const percent = (value: number | null | undefined) => (value === null || value === undefined ? "–" : `${value}%`);
  const totals = analytics.data?.totals;
  const rows = analytics.data?.events ?? [];

  return (
    <div {...guideAnchor("events.analytics")} className="flex flex-col gap-4">
      <ScopePicker value={scope} onChange={setScope} />
      {analytics.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{tEvents("loading")}</p>
      ) : (
        <>
          {totals ? (
            <HubCard eyebrow={t("totalsAll", { count: totals.events })}>
              <div className="grid grid-cols-2 gap-2">
                <Stat label={t("viewers")} value={String(totals.viewers)} />
                <Stat label={t("rsvps")} value={String(totals.rsvps)} />
                <Stat label={t("waitlisted")} value={String(totals.waitlisted)} />
                <Stat label={t("came")} value={String(totals.came)} />
                <Stat label={t("attendance")} value={percent(totals.attendance_rate)} />
                <Stat label={t("conversion")} value={percent(totals.conversion_rate)} />
              </div>
              <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("viewsPrivacy")}</p>
            </HubCard>
          ) : null}
          <HubCard eyebrow={t("perEvent")}>
            {rows.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("analyticsEmpty")}</p>
            ) : (
              <ul className="flex flex-col gap-2">
                {rows.map((row) => (
                  <li key={row.event_id} className="flex flex-col gap-1 rounded-2xl px-3 py-3" style={{ background: "var(--panel-raised)" }}>
                    <span className="font-bold" style={{ color: "var(--text)", textDecoration: row.cancelled_at ? "line-through" : undefined }}>{row.title}</span>
                    <span className="text-xs" style={{ color: "var(--dim)" }}>{formatWhen(row.starts_at, row.ends_at ?? row.starts_at, locale, row.time_zone)}</span>
                    <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
                      {[
                        t("viewersLine", { count: row.viewers }),
                        t("rsvpsLine", { count: row.rsvps }),
                        row.waitlisted ? t("waitlistedLine", { count: row.waitlisted }) : null,
                        row.attendance_rate === null || row.attendance_rate === undefined ? null : t("attendanceLine", { rate: row.attendance_rate }),
                        row.conversion_rate === null || row.conversion_rate === undefined ? null : t("conversionLine", { rate: row.conversion_rate }),
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </HubCard>
        </>
      )}
    </div>
  );
}

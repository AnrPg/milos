"use client";

import Link from "next/link";
import { useEffect, useState, useSyncExternalStore } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { fetchCalendarExportLinks } from "@/api/calendar";
import {
  cancelEvent,
  createEventInvite,
  eventKey,
  fetchEvent,
  recordEventView,
  updateEvent,
  type CommunityEvent,
  type EventScope,
} from "@/api/events";
import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { blockPerson } from "@/api/partners";
import { MoreMenu } from "@/components/community/PostCard";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { mapsSearchUrl, mapsUrl, readApple, serverApple, subscribeNever } from "@/lib/maps";
import { can } from "@/lib/role-navigation";

import { eventHostMode, formFromEvent, formatPrice, formatWhen, placeAddress, placeName } from "./events";
import { EventEditorSheet, ScopePicker, useEventLocations } from "./EventEditorSheet";
import { DateBlock, Goers, RsvpButton, useEventError } from "./EventParts";
import { invalidateEvents } from "./use-events";
import { useEventReferral } from "@/components/referrals/use-referral-link";
import { YourTime } from "@/components/zoned-time";

/**
 * The event page (board 8 Q2–Q4): cover, when, where with directions, the
 * price (paid at the box), who may come, who's going, «Θα έρθω» and, once
 * going, «Φέρε φίλο» and the calendar. Opened from a guest pass link it says
 * who invited and takes the place as their guest. Whoever runs the event
 * edits or cancels it here; staff also open its attendee list.
 */
export function EventPage({
  eventId,
  invite,
  referral = null,
}: {
  eventId: string;
  invite: string | null;
  referral?: string | null;
}) {
  const t = useTranslations("Events");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  useEventReferral(referral, eventId, invite ? "guest_pass" : "event");
  const event = useQuery({
    queryKey: eventKey(eventId, invite),
    enabled: Boolean(token),
    queryFn: () => fetchEvent(token!, eventId, invite),
  });

  if (event.isPending) {
    return (
      <HubPage title={t("eventTitle")}>
        <p style={{ color: "var(--dim)" }}>{t("loading")}</p>
      </HubPage>
    );
  }
  if (!event.data) {
    return (
      <HubPage title={t("eventTitle")}>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("eventNotFound")}</p>
        <Link href="/events" className="text-sm font-semibold underline" style={{ color: "var(--text)" }}>{t("allEvents")}</Link>
      </HubPage>
    );
  }
  return <EventView event={event.data} invite={invite} />;
}

/** ADR-185: counts this open of the page once (the API keeps no viewer, and skips hosts). */
function useCountView(eventId: string) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  useEffect(() => {
    if (!token) return;
    recordEventView(token, eventId).catch(() => undefined);
  }, [token, eventId]);
}

function EventView({ event, invite }: { event: CommunityEvent; invite: string | null }) {
  const t = useTranslations("Events");
  const locale = useLocale();
  useCountView(event.id);
  const apple = useSyncExternalStore(subscribeNever, readApple, serverApple);
  const price = formatPrice(event.price_cents, event.currency, locale);
  const invitation = event.invitation ?? null;
  const going = event.my?.status === "going";
  const address = placeAddress(event.place);
  const directions =
    event.place.latitude != null && event.place.longitude != null
      ? mapsUrl({ latitude: event.place.latitude, longitude: event.place.longitude }, placeName(event.place), apple)
      : address || event.place.name
        ? mapsSearchUrl([event.place.name, address].filter(Boolean).join(", "), apple)
        : null;
  const personHost = event.host?.kind === "person";
  const who = event.open_to_non_members
    ? t("openToAll")
    : event.group && (event.audience ?? "group") === "group"
      ? t("whoGroup", { group: event.group.name ?? "" })
      : personHost
        ? t("whoSelfInvite")
        : t("membersOnly");
  const spots = event.cancelled
    ? null
    : event.spots_left === 0
      ? event.waitlist_count > 0
        ? t("fullWaitlist", { count: event.waitlist_count })
        : t("full")
      : event.spots_left != null
        ? t("spotsLeft", { count: event.spots_left })
        : null;

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-6 pt-4">
      <div className="relative overflow-hidden rounded-3xl" style={{ background: "linear-gradient(135deg, var(--primary), color-mix(in srgb, var(--primary) 30%, var(--bg)))" }}>
        {event.cover_url ? (
          // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
          <img src={event.cover_url} alt="" className="aspect-[16/7] w-full object-cover" />
        ) : (
          <div className="aspect-[16/7] w-full" />
        )}
        <span className="absolute bottom-3 start-3 rounded-xl" style={{ boxShadow: "var(--shadow-md)" }}>
          <DateBlock iso={event.starts_at} size="lg" timeZone={event.time_zone} />
        </span>
      </div>

      <header className="flex flex-col gap-1">
        <p className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
          {event.goers != null ? (
            <Link href={`/clubs/${event.club_id}`}>{[event.club.name, event.group?.name].filter(Boolean).join(" › ")}</Link>
          ) : (
            [event.box.name, event.club.name].filter(Boolean).join(" · ")
          )}
        </p>
        <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)", textDecoration: event.cancelled ? "line-through" : undefined }}>
          {event.title}
        </h1>
        <EventHosts event={event} />
      </header>

      {event.cancelled ? (
        <p role="status" className="rounded-2xl px-4 py-3 text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--danger) 14%, var(--panel))", color: "var(--text)" }}>
          {event.cancel_reason ? t("cancelledWithReason", { reason: event.cancel_reason }) : t("cancelledNotice")}
        </p>
      ) : null}

      {invitation ? (
        <section className="flex items-center gap-3 rounded-3xl p-4" style={{ background: "color-mix(in srgb, var(--primary) 10%, var(--panel))", border: "1px solid color-mix(in srgb, var(--primary) 45%, transparent)" }}>
          <PersonAvatar name={invitation.inviter.nickname} url={invitation.inviter.avatar_url} />
          <div className="min-w-0">
            <p className="font-bold" style={{ color: "var(--text)" }}>{t("invitedBy", { name: invitation.inviter.nickname ?? "?" })}</p>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>
              {invitation.usable ? t("invitedHint") : t(["inviteReason", invitation.reason ?? "unknown"].join("_"))}
            </p>
          </div>
        </section>
      ) : null}

      <HubCard>
        <dl className="flex flex-col gap-3 text-sm">
          <InfoRow label={t("infoWhen")}>
            <span className="first-letter:uppercase">{formatWhen(event.starts_at, event.ends_at, locale, event.time_zone)}</span>
            <YourTime at={event.starts_at} zone={event.time_zone} format="day-time" />
          </InfoRow>
          <InfoRow label={t("infoWhere")}>
            <span className="flex flex-col">
              <span>{placeName(event.place) || t("placeUnknown")}</span>
              {address && address !== placeName(event.place) ? <span style={{ color: "var(--text-soft)" }}>{address}</span> : null}
              {directions ? (
                <a href={directions} target="_blank" rel="noreferrer" className="mt-1 text-sm font-bold" style={{ color: "var(--primary-strong, var(--primary))" }}>
                  {t("directions")}
                </a>
              ) : null}
            </span>
          </InfoRow>
          <InfoRow label={t("infoPrice")}>
            <span>{price ? [price, t("payAtBox")].join(" · ") : t("free")}</span>
          </InfoRow>
          <InfoRow label={t("infoWho")}>
            <span>
              {[who, event.guest_pass_allowed ? t("guestPassLine", { count: event.guests_per_member }) : null].filter(Boolean).join(" · ")}
            </span>
          </InfoRow>
        </dl>
        {event.description ? (
          <p className="mt-4 whitespace-pre-wrap text-sm" style={{ color: "var(--text)" }}>{event.description}</p>
        ) : null}
      </HubCard>

      <HubCard>
        <div className="flex flex-col gap-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <Goers event={event} />
            {spots ? <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{spots}</span> : null}
          </div>
          {event.goers && event.goers.length > 0 ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>
              {event.goers.map((person) => person.nickname ?? "?").join(", ")}
            </p>
          ) : null}
          <div className="flex flex-col gap-2">
            <RsvpButton event={event} inviteToken={invitation?.usable ? invite : null} />
          </div>
          {going && event.price_cents > 0 ? (
            <p className="text-sm font-semibold" style={{ color: event.my?.paid ? "var(--success)" : "var(--text-soft)" }}>
              {event.my?.paid ? t("paidDone") : t("payAtBoxLong", { price: price ?? "" })}
            </p>
          ) : null}
          {going && !event.can_manage ? <GuestPass event={event} /> : null}
          {going ? <AddToCalendar /> : null}
        </div>
      </HubCard>

      {event.can_manage ? <ManageEvent event={event} /> : null}
    </main>
  );
}

/**
 * ADR-185: who hosts it (a person or a business) and the boxes that
 * co-host it. A person's own event can be blocked from here: their events
 * and posts no longer show to you.
 */
function EventHosts({ event }: { event: CommunityEvent }) {
  const t = useTranslations("Events");
  const eventError = useEventError();
  const { tokens, currentUser } = useSession();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const host = event.host;
  const block = useMutation({
    mutationFn: () => blockPerson(tokens!.access_token, host!.person!.id),
    onSuccess: async () => {
      await invalidateEvents(queryClient);
      router.push("/events");
    },
  });
  if (!host) return null;
  const cohosts = event.cohosts ?? [];
  const name = host.name ?? host.person?.nickname ?? "?";
  const href = host.kind === "person" ? (host.person ? `/people/${host.person.id}` : null) : host.slug ? `/b/${host.slug}` : null;
  const blockable = host.kind === "person" && host.person && host.person.id !== currentUser?.id && !event.can_manage;

  return (
    <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm" style={{ color: "var(--text-soft)" }}>
      <span>
        {t("hostedBy")}{" "}
        {href ? (
          <Link href={href} className="font-semibold" style={{ color: "var(--text)" }}>{name}</Link>
        ) : (
          <span className="font-semibold" style={{ color: "var(--text)" }}>{name}</span>
        )}
      </span>
      {cohosts.length > 0 ? (
        <span>
          {t("withCohosts")}{" "}
          {cohosts.map((cohost, index) => (
            <span key={cohost.organization_id}>
              {index > 0 ? ", " : null}
              {cohost.slug ? (
                <Link href={`/b/${cohost.slug}`} className="font-semibold" style={{ color: "var(--text)" }}>{cohost.name ?? "?"}</Link>
              ) : (
                <span className="font-semibold" style={{ color: "var(--text)" }}>{cohost.name ?? "?"}</span>
              )}
            </span>
          ))}
        </span>
      ) : null}
      {blockable ? (
        <MoreMenu label={t("hostActions", { name })} items={[{ label: t("blockHost", { name }), onSelect: () => setConfirming(true) }]} />
      ) : null}
      {confirming ? (
        <Sheet
          labelId={["block-host", event.id].join("-")}
          eyebrow={event.title}
          title={t("blockHost", { name })}
          onClose={() => setConfirming(false)}
          footer={
            <>
              <SheetButton onClick={() => setConfirming(false)}>{t("keepEvent")}</SheetButton>
              <SheetButton primary disabled={block.isPending} onClick={() => block.mutate()}>{t("blockConfirm")}</SheetButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("blockHostBody", { name })}</p>
          <ErrorLine message={eventError(block.error)} />
        </Sheet>
      ) : null}
    </div>
  );
}

function InfoRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[6rem_minmax(0,1fr)] gap-3">
      <dt className="text-xs font-bold uppercase tracking-[0.12em]" style={{ color: "var(--dim)" }}>{label}</dt>
      <dd style={{ color: "var(--text)" }}>{children}</dd>
    </div>
  );
}

/**
 * «Φέρε φίλο» (board 8 Q4): a guest pass link to share or copy, with the
 * guests left. ADR-185: the host's own link (`host`) has no guest limit and
 * is how people come to an invitation-only event.
 */
function GuestPass({ event, host = false }: { event: CommunityEvent; host?: boolean }) {
  const t = useTranslations("Events");
  const eventError = useEventError();
  const { tokens } = useSession();
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const invite = useMutation({ mutationFn: () => createEventInvite(tokens!.access_token, event.id) });
  if (!host && !event.guest_pass_allowed) return null;
  const left = host ? 1 : (invite.data?.guests_left ?? event.guests_left ?? 0);
  const label = host ? t("hostInvite") : t("bringFriend");
  const link = invite.data ? window.location.origin + invite.data.path : "";

  async function share() {
    if (!link) return;
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: event.title, text: t("shareText", { title: event.title }), url: link });
        return;
      } catch {
        // Closed the share sheet: fall back to copying.
      }
    }
    await copy();
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  return (
    <>
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          disabled={left <= 0}
          onClick={() => {
            setOpen(true);
            if (!invite.data && !invite.isPending) invite.mutate();
          }}
          className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {label}
        </button>
        {host ? null : <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("guestsLeft", { count: left })}</span>}
      </div>
      {open ? (
        <Sheet
          labelId={["guest-pass", event.id].join("-")}
          eyebrow={event.title}
          title={label}
          onClose={() => setOpen(false)}
          footer={
            <>
              <SheetButton onClick={() => void copy()} disabled={!link}>{copied ? t("copied") : t("copyLink")}</SheetButton>
              <SheetButton primary onClick={() => void share()} disabled={!link}>{t("shareLink")}</SheetButton>
            </>
          }
        >
          <div className="flex flex-col gap-3">
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{host ? t("hostInviteBody") : t("bringFriendBody", { count: left })}</p>
            {invite.isPending ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
            {link ? (
              <Field label={t("inviteLink")}>
                <input readOnly value={link} onFocus={(focus) => focus.currentTarget.select()} className="min-h-11 rounded-2xl px-3 text-sm font-normal" style={inputStyle} />
              </Field>
            ) : null}
            <span role="status" className="sr-only">{copied ? t("copied") : ""}</span>
            <ErrorLine message={eventError(invite.error)} />
          </div>
        </Sheet>
      ) : null}
    </>
  );
}

/** Going events are in the member's calendar feed; this subscribes their calendar to it. */
function AddToCalendar() {
  const t = useTranslations("Events");
  const eventError = useEventError();
  const { tokens } = useSession();
  const subscribe = useMutation({
    mutationFn: () => fetchCalendarExportLinks(tokens!.access_token),
    onSuccess: (links) => {
      window.location.href = links.webcal_url;
    },
  });
  return (
    <div className="flex flex-col gap-1">
      <button
        type="button"
        disabled={subscribe.isPending}
        onClick={() => subscribe.mutate()}
        className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
        style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
      >
        {t("addToCalendar")}
      </button>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("addToCalendarHint")}</p>
      <ErrorLine message={eventError(subscribe.error)} />
    </div>
  );
}

/** Edit and cancel for whoever runs the event; staff also open its attendee list. */
function ManageEvent({ event }: { event: CommunityEvent }) {
  const t = useTranslations("Events");
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const { memberships } = useSelectedMembershipRole();
  const membership = memberships.find((entry) => entry.organization.slug === event.box.slug) ?? null;
  const own = event.host?.kind === "person";
  const staff = can(membership, "manage_events") || can(membership, "check_in") || can(membership, "take_payments");
  const locations = useEventLocations(own ? null : event.box.slug);
  const groupOnly = (event.audience ?? (event.channel_id ? "group" : "club")) === "group";
  // ADR-185: a person's own event, and any event run from the organiser console, opens there.
  const consoleHref = event.host ? `/events/hosting?org=${encodeURIComponent(event.organization_id)}&event=${encodeURIComponent(event.id)}` : null;
  const [editing, setEditing] = useState(false);
  const [cancelling, setCancelling] = useState(false);

  async function saved(fresh: CommunityEvent) {
    queryClient.setQueriesData({ queryKey: ["events", "event", event.id] }, (current: CommunityEvent | undefined) =>
      current ? { ...current, ...fresh } : current,
    );
    await invalidateEvents(queryClient);
  }

  return (
    <HubCard eyebrow={t("manageTitle")}>
      <div className="flex flex-wrap gap-2">
        {!event.cancelled ? (
          <>
            <SheetButton onClick={() => setEditing(true)}>{t("edit")}</SheetButton>
            <SheetButton onClick={() => setCancelling(true)}>{t("cancelEvent")}</SheetButton>
          </>
        ) : null}
        {!event.cancelled && !groupOnly ? <GuestPass event={event} host /> : null}
        {own && consoleHref ? (
          <Link
            href={consoleHref}
            className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("openAttendees")}
          </Link>
        ) : staff && event.box.slug ? (
          <Link
            href={`/org/${event.box.slug}/admin/community/events/${event.id}`}
            className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("openAttendees")}
          </Link>
        ) : null}
      </div>
      {editing ? (
        <EventEditorSheet
          title={t("edit")}
          eyebrow={event.title}
          initial={formFromEvent(event)}
          initialCoverUrl={event.cover_url ?? null}
          editing={{ seriesId: event.series_id ?? null }}
          group={Boolean(event.channel_id)}
          mode={eventHostMode({ own, group: Boolean(event.channel_id) })}
          locations={locations.data ?? []}
          coverSlug={!own && can(membership, "manage_settings") ? event.box.slug : null}
          gymSlug={own ? null : event.box.slug}
          onSubmit={async (body, scope) => saved(await updateEvent(tokens!.access_token, event.id, { ...body, scope }))}
          onClose={() => setEditing(false)}
        />
      ) : null}
      {cancelling ? (
        <CancelEventSheet
          event={event}
          onCancel={async (reason, scope) => saved(await cancelEvent(tokens!.access_token, event.id, reason, scope))}
          onClose={() => setCancelling(false)}
        />
      ) : null}
    </HubCard>
  );
}

/** «Ακύρωση event» (board 8 Q6): why, and for a weekly event this one or the following too. */
export function CancelEventSheet({
  event,
  onCancel,
  onClose,
}: {
  event: Pick<CommunityEvent, "id" | "title" | "series_id" | "going_count">;
  onCancel: (reason: string | null, scope: EventScope) => Promise<unknown>;
  onClose: () => void;
}) {
  const t = useTranslations("Events");
  const eventError = useEventError();
  const [reason, setReason] = useState("");
  const [scope, setScope] = useState<EventScope>("this");
  const cancel = useMutation({ mutationFn: () => onCancel(reason.trim() || null, scope), onSuccess: onClose });
  return (
    <Sheet
      labelId={["cancel-event", event.id].join("-")}
      eyebrow={event.title}
      title={t("cancelEventTitle")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("keepEvent")}</SheetButton>
          <SheetButton primary disabled={cancel.isPending} onClick={() => cancel.mutate()}>{t("cancelEvent")}</SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("cancelEventBody", { count: event.going_count })}</p>
        <Field label={t("cancelReason")}>
          <input value={reason} maxLength={300} onChange={(change) => setReason(change.target.value)} placeholder={t("cancelReasonPlaceholder")} className="min-h-11 rounded-2xl px-3 text-sm font-normal" style={inputStyle} />
        </Field>
        {event.series_id ? <ScopePicker value={scope} onChange={setScope} /> : null}
        <ErrorLine message={eventError(cancel.error)} />
      </div>
    </Sheet>
  );
}

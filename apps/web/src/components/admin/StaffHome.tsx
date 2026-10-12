"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState, type ReactNode } from "react";

import { fetchAthletes } from "@/api/admin";
import { fetchCleaningAreas, fetchCoachingRelationships, startCoachingRelationship } from "@/api/roles";
import { fetchSchedule, type ScheduleSlot } from "@/api/schedule";
import { fetchAppointmentSlots } from "@/api/staff";
import { AdminDashboard } from "@/components/admin/AdminDashboard";
import { classesCoachedToday, roleErrorKey, staffHomeLayout, takeableAthletes } from "@/components/admin/staff-home";
import { formatDateTime } from "@/components/client/format";
import { useSession } from "@/components/session-provider";
import { CleaningLog } from "@/components/staff/CleaningLog";
import { FormReviewQueue } from "@/components/staff/FormReviewQueue";
import { ReplyQueue } from "@/components/staff/ReplyQueue";
import {
  inputClass,
  inputStyle,
  Pill,
  secondaryButtonClass,
  secondaryButtonStyle,
  StatusText,
} from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { can } from "@/lib/role-navigation";

// The staff home (ADR-103, docs/architecture/navigation-by-role.md): owners
// and admins keep the dashboard; a janitor gets the cleaning log; everyone
// else gets small sections for the roles they hold, linking to the full pages.

type Membership = ReturnType<typeof useSelectedMembershipRole>["membership"];
type HomeLink = { label: string; href: string; hint?: ReactNode };

const RELATIONSHIPS_KEY = ["staff", "coaching-relationships"] as const;

export function StaffHome() {
  const i18n = useUiTranslations();
  const { membership, isLoading } = useSelectedMembershipRole();
  const layout = staffHomeLayout(membership);

  if (layout.kind === "loading") {
    return (
      <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
        <StatusText tone="muted">{isLoading ? i18n("loading33ce417") : i18n("rhNoGym")}</StatusText>
      </main>
    );
  }

  if (layout.kind === "cleaning") {
    return (
      <>
        {can(membership, "report_inventory") ? <InventoryShortcut /> : null}
        <CleaningLog />
      </>
    );
  }

  if (layout.kind === "admin") {
    return (
      <>
        <AdminDashboard />
        {layout.coach ? (
          <div className="px-4 pb-10 md:px-10" style={{ background: "var(--bg)" }}>
            <div className="mx-auto max-w-6xl">
              <MyClientsSection membership={membership} />
            </div>
          </div>
        ) : null}
      </>
    );
  }

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-5xl flex-col gap-4">
        <header>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
            {membership?.organization.name}
          </p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
            {i18n("rhStaffHomeTitle")}
          </h1>
        </header>
        {layout.sections.includes("coach") ? <CoachSections membership={membership} /> : null}
        {layout.sections.includes("front_desk") ? <FrontDeskSections membership={membership} /> : null}
        {layout.sections.includes("accountant") ? <AccountantSections membership={membership} /> : null}
        {layout.sections.includes("cleaning") ? (
          <HomeSection id="home-cleaning" title={i18n("rhCleaning")}>
            <LinkList links={[{ label: i18n("rhOpenCleaningLog"), href: "/admin/cleaning" }]} />
          </HomeSection>
        ) : null}
        {can(membership, "report_inventory") || can(membership, "manage_inventory") ? (
          <HomeSection id="home-inventory" title={i18n("invEyebrow")}>
            <LinkList
              links={[
                { label: i18n("invTabMachines"), href: "/admin/inventory?tab=machines" },
                { label: i18n("invTabSupplies"), href: "/admin/inventory?tab=supplies" },
              ]}
            />
          </HomeSection>
        ) : null}
        {layout.sections.length === 0 && !can(membership, "report_inventory") && !can(membership, "manage_inventory") ? (
          <StatusText tone="muted">{i18n("rhNothingHere")}</StatusText>
        ) : null}
      </div>
    </main>
  );
}

/** The janitor's home is the cleaning log; inventory sits one tap above it (ADR-104). */
function InventoryShortcut() {
  const i18n = useUiTranslations();
  const organizationSlug = useOrganizationSlug();
  return (
    <div className="px-4 pt-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-5xl justify-end">
        <Link href={adminHref("/admin/inventory", organizationSlug)} className={secondaryButtonClass} style={secondaryButtonStyle}>
          {i18n("invOpenInventory")}
        </Link>
      </div>
    </div>
  );
}

/** A collapsible panel in the style of the user profile sections. */
export function HomeSection({
  id,
  title,
  badge,
  defaultOpen = false,
  children,
}: {
  id: string;
  title: string;
  badge?: ReactNode;
  defaultOpen?: boolean;
  children: ReactNode;
}) {
  const i18n = useUiTranslations();
  const [open, setOpen] = useState(defaultOpen);
  return (
    <article id={id} className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <button
        type="button"
        aria-expanded={open}
        aria-controls={`${id}-content`}
        onClick={() => setOpen((value) => !value)}
        className="flex w-full items-center justify-between gap-3 px-5 py-4 text-start"
      >
        <span className="flex min-w-0 items-center gap-2">
          <span className="truncate text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>
            {title}
          </span>
          {badge}
        </span>
        <span className="shrink-0 text-sm font-semibold" style={{ color: "var(--dim)" }}>
          {open ? i18n("hide34d8b60") : i18n("showd97d1ee")}
        </span>
      </button>
      {open ? (
        <div id={`${id}-content`} className="border-t px-5 pb-5 pt-4 text-sm" style={{ borderColor: "var(--border)", color: "var(--text-soft)" }}>
          {children}
        </div>
      ) : null}
    </article>
  );
}

function LinkList({ links }: { links: HomeLink[] }) {
  const organizationSlug = useOrganizationSlug();
  if (links.length === 0) return null;
  return (
    <ul className="space-y-2">
      {links.map((link) => (
        <li key={link.href + link.label}>
          <Link
            href={adminHref(link.href, organizationSlug)}
            className="flex items-center justify-between gap-3 rounded-[1.2rem] px-4 py-3"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <span className="min-w-0">
              <span className="block truncate font-semibold" style={{ color: "var(--text)" }}>{link.label}</span>
              {link.hint ? <span className="mt-0.5 block text-xs" style={{ color: "var(--dim)" }}>{link.hint}</span> : null}
            </span>
            <span aria-hidden className="shrink-0" style={{ color: "var(--primary)" }}>→</span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

function QuickActions({ links }: { links: HomeLink[] }) {
  const organizationSlug = useOrganizationSlug();
  if (links.length === 0) return null;
  return (
    <div className="flex flex-wrap gap-2">
      {links.map((link) => (
        <Link key={link.href + link.label} href={adminHref(link.href, organizationSlug)} className={secondaryButtonClass} style={secondaryButtonStyle}>
          {link.label}
        </Link>
      ))}
    </div>
  );
}

function CoachSections({ membership }: { membership: Membership }) {
  const i18n = useUiTranslations();
  const has = (capability: string) => can(membership, capability);
  const tools: HomeLink[] = [
    ...(has("manage_coaching") ? [{ label: i18n("rhNutritionPlans"), href: "/admin/coaching?tab=nutrition" }] : []),
    ...(has("view_coaching_analytics") ? [{ label: i18n("rhCoachingReports"), href: "/admin/metrics/coaching" }] : []),
    ...(has("manage_content") ? [{ label: i18n("rhContent"), href: "/admin/content" }] : []),
    ...(has("manage_challenges") ? [{ label: i18n("rhChallenges"), href: "/admin/challenges" }] : []),
  ];

  return (
    <>
      <MyClassesToday />
      <MyClientsSection membership={membership} />
      {has("manage_coaching") ? <ReplyQueue /> : null}
      {has("manage_coaching") ? <FormReviewQueue /> : null}
      {has("manage_appointments") ? <MyAppointments /> : null}
      {tools.length > 0 ? (
        <HomeSection id="home-coach-tools" title={i18n("rhCoachingTools")}>
          <LinkList links={tools} />
        </HomeSection>
      ) : null}
    </>
  );
}

function MyClassesToday() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const query = useQuery({
    queryKey: ["staff", "home", "classes-today"],
    enabled: Boolean(token),
    queryFn: () => {
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      const end = new Date(start);
      end.setDate(start.getDate() + 1);
      return fetchSchedule(token!, { startAt: start.toISOString(), endAt: end.toISOString(), days: 3, classTypeIds: [] });
    },
  });
  // ADR-100: a class carries its coach; the schedule payload includes it.
  const slots = (query.data?.slots ?? []) as Array<ScheduleSlot & { coach_user_id?: string | null }>;
  const mine = classesCoachedToday(slots, currentUser?.id);
  const time = (iso: string) => new Intl.DateTimeFormat(locale, { timeStyle: "short" }).format(new Date(iso));

  return (
    <HomeSection
      id="home-classes-today"
      title={i18n("rhMyClassesToday")}
      badge={query.data ? <Pill tone={mine.length ? "primary" : "neutral"}>{mine.length}</Pill> : null}
      defaultOpen
    >
      {query.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : query.isError ? (
        <StatusText tone="error">{localizeError(query.error, i18n)}</StatusText>
      ) : (
        <div className="space-y-3">
          <p style={{ color: "var(--muted)" }}>{i18n("rhClassesTodayCount", { count: mine.length })}</p>
          <LinkList
            links={[
              ...mine.map((slot) => ({
                label: `${time(slot.scheduled_at)} · ${slot.name}`,
                href: `/admin/class-schedule?open_slot=${slot.id}`,
                hint: i18n("rhBookedCount", { count: slot.approved_booking_count, capacity: slot.capacity }),
              })),
              { label: i18n("rhOpenCoaching"), href: "/admin/class-schedule" },
            ]}
          />
        </div>
      )}
    </HomeSection>
  );
}

/** The coach's own clients (ADR-100), with "Take an athlete". */
export function MyClientsSection({ membership }: { membership: Membership }) {
  const i18n = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const organizationSlug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [taking, setTaking] = useState(false);
  const [search, setSearch] = useState("");
  const [showAll, setShowAll] = useState(false);

  const clients = useQuery({
    queryKey: [...RELATIONSHIPS_KEY, { coach: currentUser?.id }],
    enabled: Boolean(token && currentUser?.id),
    queryFn: () => fetchCoachingRelationships(token!, { coachUserId: currentUser!.id }),
  });
  const athletes = useQuery({
    queryKey: ["staff", "home", "athletes", search.trim()],
    enabled: Boolean(token) && taking,
    queryFn: () => fetchAthletes(token!, search.trim() || undefined),
  });
  const take = useMutation({
    mutationFn: (clientUserId: string) => startCoachingRelationship(token!, clientUserId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: RELATIONSHIPS_KEY });
      await queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
    },
  });

  const relationships = clients.data ?? [];
  const visible = showAll ? relationships : relationships.slice(0, 8);
  const candidates = takeableAthletes(athletes.data?.athletes ?? [], relationships.map((item) => item.client_user_id)).slice(0, 8);
  const canTake = can(membership, "self_assign_athletes");
  const takeError = take.isError ? (roleErrorKey(take.error) ? i18n(roleErrorKey(take.error)!) : localizeError(take.error, i18n)) : null;

  return (
    <HomeSection
      id="home-my-clients"
      title={i18n("rhMyClients")}
      badge={clients.data ? <Pill tone="neutral">{relationships.length}</Pill> : null}
      defaultOpen
    >
      <div className="space-y-3">
        {clients.isPending ? (
          <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
        ) : clients.isError ? (
          <StatusText tone="error">{localizeError(clients.error, i18n)}</StatusText>
        ) : relationships.length === 0 ? (
          <StatusText tone="muted">{i18n("rhNoClients")}</StatusText>
        ) : (
          <ul className="grid gap-2">
            {visible.map((item) => (
              <li key={item.id}>
                <Link
                  href={adminHref(`/admin/users/${item.client_user_id}`, organizationSlug)}
                  className="flex items-center justify-between gap-3 rounded-[1.2rem] px-4 py-3"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                >
                  <span className="min-w-0 truncate font-semibold" style={{ color: "var(--text)" }}>
                    {item.client_nickname ?? i18n("stfUnknownMember")}
                  </span>
                  <span className="shrink-0 text-sm font-semibold" style={{ color: "var(--primary)" }}>{i18n("open6f4789b")}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
        <div className="flex flex-wrap gap-2">
          {relationships.length > 8 ? (
            <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setShowAll((value) => !value)}>
              {showAll ? i18n("rhShowFewer") : i18n("rhShowAllClients", { count: relationships.length })}
            </button>
          ) : null}
          {canTake ? (
            <button
              type="button"
              aria-expanded={taking}
              className={secondaryButtonClass}
              style={secondaryButtonStyle}
              onClick={() => {
                setTaking((value) => !value);
                take.reset();
              }}
            >
              {taking ? i18n("cancel77dfd21") : i18n("rhTakeAthlete")}
            </button>
          ) : null}
        </div>
        {taking ? (
          <div className="space-y-2 rounded-[1.2rem] p-3" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}>
            <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("rhTakeAthleteHelp")}</p>
            <input
              aria-label={i18n("rhSearchAthletes")}
              placeholder={i18n("rhSearchAthletes")}
              className={inputClass}
              style={inputStyle}
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
            {athletes.isPending ? (
              <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
            ) : athletes.isError ? (
              <StatusText tone="error">{localizeError(athletes.error, i18n)}</StatusText>
            ) : candidates.length === 0 ? (
              <StatusText tone="muted">{i18n("rhNoAthletesToTake")}</StatusText>
            ) : (
              <ul className="grid gap-2">
                {candidates.map((athlete) => (
                  <li key={athlete.id} className="flex items-center justify-between gap-3">
                    <span className="min-w-0 truncate" style={{ color: "var(--text)" }}>{athlete.nickname}</span>
                    <button
                      type="button"
                      disabled={take.isPending}
                      className={secondaryButtonClass}
                      style={secondaryButtonStyle}
                      onClick={() => take.mutate(athlete.id)}
                    >
                      {i18n("rhTake")}
                    </button>
                  </li>
                ))}
              </ul>
            )}
            {takeError ? <StatusText tone="error">{takeError}</StatusText> : null}
            {take.isSuccess ? <StatusText tone="success">{i18n("rhAthleteTaken")}</StatusText> : null}
          </div>
        ) : null}
      </div>
    </HomeSection>
  );
}

function MyAppointments() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const query = useQuery({
    queryKey: ["staff", "home", "appointments", currentUser?.id],
    enabled: Boolean(token && currentUser?.id),
    queryFn: () => {
      const from = new Date();
      const to = new Date(from);
      to.setDate(from.getDate() + 7);
      return fetchAppointmentSlots(token!, { from: from.toISOString(), to: to.toISOString(), coach_id: currentUser!.id });
    },
  });
  const slots = (query.data ?? []).filter((slot) => !slot.cancelled_at).sort((a, b) => a.starts_at.localeCompare(b.starts_at));
  const booked = (slot: (typeof slots)[number]) => (slot.bookings ?? []).filter((booking) => booking.status === "booked").length;

  return (
    <HomeSection
      id="home-appointments"
      title={i18n("rhMyAppointments")}
      badge={query.data ? <Pill tone="neutral">{slots.length}</Pill> : null}
    >
      {query.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : query.isError ? (
        <StatusText tone="error">{localizeError(query.error, i18n)}</StatusText>
      ) : (
        <div className="space-y-3">
          <p style={{ color: "var(--muted)" }}>{i18n("rhAppointmentsThisWeek", { count: slots.length })}</p>
          <LinkList
            links={[
              ...slots.slice(0, 5).map((slot) => ({
                label: formatDateTime(slot.starts_at, locale),
                href: "/admin/appointments",
                hint: i18n("rhBookedCount", { count: booked(slot), capacity: slot.capacity }),
              })),
              { label: i18n("rhOpenAppointments"), href: "/admin/appointments" },
            ]}
          />
        </div>
      )}
    </HomeSection>
  );
}

function FrontDeskSections({ membership }: { membership: Membership }) {
  const i18n = useUiTranslations();
  const has = (capability: string) => can(membership, capability);
  const today: HomeLink[] = [
    ...(has("check_in") ? [{ label: i18n("rhArrivalsNow"), href: "/admin/check-in" }] : []),
    ...(has("run_classes") ? [{ label: i18n("rhTodaysClasses"), href: "/admin/class-schedule" }] : []),
  ];
  const actions: HomeLink[] = [
    ...(has("invite_clients") ? [{ label: i18n("rhNewClient"), href: "/admin/finance?tab=members" }] : []),
    ...(has("take_payments") ? [{ label: i18n("rhSellPackage"), href: "/admin/finance" }] : []),
    ...(has("take_payments") ? [{ label: i18n("rhTakePayment"), href: "/admin/finance?tab=queues" }] : []),
  ];

  return (
    <>
      {today.length > 0 || actions.length > 0 ? (
        <HomeSection id="home-front-desk" title={i18n("rhFrontDesk")} defaultOpen>
          <div className="space-y-3">
            <LinkList links={today} />
            <QuickActions links={actions} />
          </div>
        </HomeSection>
      ) : null}
      {has("review_cleaning") || has("record_cleaning") ? <CleaningStatus /> : null}
    </>
  );
}

function CleaningStatus() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const areas = useQuery({
    queryKey: ["staff", "cleaning", "areas"],
    enabled: Boolean(token),
    queryFn: () => fetchCleaningAreas(token!),
  });
  const active = (areas.data ?? []).filter((area) => !area.archived_at);

  return (
    <HomeSection id="home-cleaning-status" title={i18n("rhCleaningStatus")}>
      {areas.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : areas.isError ? (
        <StatusText tone="error">{localizeError(areas.error, i18n)}</StatusText>
      ) : active.length === 0 ? (
        <StatusText tone="muted">{i18n("cleanNoAreas")}</StatusText>
      ) : (
        <ul className="grid gap-2">
          {active.map((area) => (
            <li
              key={area.id}
              className="flex flex-wrap items-center justify-between gap-2 rounded-[1.2rem] px-4 py-3"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
            >
              <span className="min-w-0 truncate font-semibold" style={{ color: "var(--text)" }}>{area.name}</span>
              <span className="text-xs" style={{ color: area.last_cleaned_at ? "var(--dim)" : "var(--warning)" }}>
                {area.last_cleaned_at
                  ? i18n("rhLastCleaned", { time: formatDateTime(area.last_cleaned_at, locale) })
                  : i18n("rhNeverCleaned")}
              </span>
            </li>
          ))}
        </ul>
      )}
    </HomeSection>
  );
}

function AccountantSections({ membership }: { membership: Membership }) {
  const i18n = useUiTranslations();
  const has = (capability: string) => can(membership, capability);
  const links: HomeLink[] = [
    ...(has("take_payments") || has("manage_billing")
      ? [
          { label: i18n("rhOverdue"), href: "/admin/finance?tab=queues", hint: i18n("rhOverdueHint") },
          { label: i18n("rhCorporateBalances"), href: "/admin/finance?tab=corporate" },
          { label: i18n("rhDeskPayments"), href: "/admin/finance?tab=members", hint: i18n("rhDeskPaymentsHint") },
        ]
      : []),
    ...(has("view_finance_reports") ? [{ label: i18n("rhFinanceReports"), href: "/admin/metrics/finance" }] : []),
  ];
  if (links.length === 0) return null;
  return (
    <HomeSection id="home-accounts" title={i18n("rhAccounts")} defaultOpen>
      <LinkList links={links} />
    </HomeSection>
  );
}

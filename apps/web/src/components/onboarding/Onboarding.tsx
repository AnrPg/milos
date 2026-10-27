"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";

import {
  completeProductTour,
  fetchAdminOnboarding,
  updateAdminOnboarding,
  type AdminOnboardingChecklist,
  type OnboardingAction,
  type OnboardingStepId,
} from "@/api/onboarding";
import { gymClubFor } from "@/components/community/community";
import { useMyClubs } from "@/components/community/use-community";
import { InviteClientsDialog } from "@/components/invites/InviteClients";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { useReportGymTimeZone } from "@/hooks/useReportGymTimeZone";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { TOUR_STEPS, checklistSnoozed, snoozeChecklist, type TourAudience } from "@/lib/onboarding";
import { setView } from "@/lib/view-mode";
import { Dialog } from "@/components/ui/Dialog";

const OPEN_TOUR_EVENT = "palee:open-tour";
const OPEN_CHECKLIST_EVENT = "palee:open-onboarding";
const HIDDEN_PATHS = /^\/(?:login|register|set-admin|join|welcome)(?:\/|$)/;

// Staff pages, opened under /org/:slug. `team` links to the club itself (see
// useTeamClubHref), so it is not here.
const STEP_LINKS: Partial<Record<OnboardingStepId, string>> = {
  timezone: "/admin/settings#time-zone",
  settings: "/admin/settings",
  classes: "/admin/class-schedule",
  packages: "/admin/finance?tab=packages",
  workout: "/admin/workouts/new",
  // ADR-170: an independent coach's practice.
  profile: "/admin/public-page",
  sessions: "/admin/appointments",
  bootcamp: "/admin/community?tab=events",
};

/** Lets any button (profile, settings) replay the tour for the current role. */
export function openProductTour() {
  window.dispatchEvent(new Event(OPEN_TOUR_EVENT));
}

export function openOnboardingChecklist() {
  window.dispatchEvent(new Event(OPEN_CHECKLIST_EVENT));
}

/**
 * Setup and tour links open staff pages. An owner who also trains may be in
 * "My training" (ADR-103), where the staff pages' guard sends them back home,
 * so following one switches back to the staff view first.
 */
function enterStaffView() {
  setView("staff");
}

/** ADR-170: the coach's «Team» is their gym club; the clubs list until it loads. */
function useTeamClubHref(enabled: boolean) {
  const clubs = useMyClubs();
  const { membership } = useSelectedMembershipRole();
  const club = enabled ? gymClubFor(clubs.data ?? [], membership?.organization.id) : null;
  return club ? `/clubs/${encodeURIComponent(club.id)}` : "/me/clubs";
}

/** Real navigation labels, so instructions always match what users see. */
function useNavigationParams() {
  const nav = useTranslations("Navigation");
  return {
    path: `${nav("utility")} → ${nav("appConfigurations")}`,
    schedule: nav("schedule"),
    myWorkouts: nav("myWorkouts"),
    pantheon: `${nav("journal")} › ${nav("progress")}`,
    billing: nav("billing"),
  };
}

function useAdminOnboarding(enabled: boolean) {
  const { tokens } = useSession();
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const token = tokens?.access_token;
  const queryKey = ["admin-onboarding", slug];

  const query = useQuery({
    queryKey,
    enabled: enabled && Boolean(token && slug),
    // A response without steps (an older API, a proxy error page) shows no
    // checklist instead of breaking the page it is mounted on.
    queryFn: async () => {
      const checklist = await fetchAdminOnboarding(token!);
      return Array.isArray(checklist?.steps) ? checklist : null;
    },
    staleTime: 30_000,
  });

  const mutation = useMutation({
    mutationFn: ({ action, step }: { action: OnboardingAction; step?: OnboardingStepId }) =>
      updateAdminOnboarding(token!, action, step),
    onSuccess: (data) => queryClient.setQueryData(queryKey, data),
  });

  return { query, mutation, slug };
}

/**
 * Mounted once in the root layout. Owners/admins get the setup checklist as a
 * popup on every login until every step is done or skipped ("Remind me later"
 * hides it for the rest of that login); every other role gets the product
 * tour on its first visit.
 */
export function OnboardingHost() {
  const pathname = usePathname();
  const { status, currentUser, tokens } = useSession();
  const { membershipRole, isLoading } = useSelectedMembershipRole();
  const ready = status === "authenticated" && Boolean(currentUser) && !currentUser?.vendor && !isLoading && Boolean(membershipRole);
  const isOwnerOrAdmin = membershipRole === "owner" || membershipRole === "admin";
  const audience: TourAudience = membershipRole === "athlete" ? "athlete" : membershipRole === "member" ? "member" : "admin";
  const { query, mutation, slug } = useAdminOnboarding(ready && isOwnerOrAdmin);
  useReportGymTimeZone(ready && isOwnerOrAdmin, tokens?.access_token, slug);
  const [tourOpen, setTourOpen] = useState(false);
  const [checklistOpen, setChecklistOpen] = useState(false);
  const [inviteOpen, setInviteOpen] = useState(false);
  // Completed tours live on the account (/auth/me), so a tour seen on one
  // device is not shown again on another. `finishedNow` covers this session.
  const [finishedNow, setFinishedNow] = useState<TourAudience[]>([]);
  const tourDone = Boolean(currentUser?.completed_tours?.includes(audience)) || finishedNow.includes(audience);
  const hidden = HIDDEN_PATHS.test(pathname);

  // Admins see the checklist popup until setup is finished, clients see the
  // tour once. The stored `dismissed` flag is no longer honoured: setup that
  // is not finished keeps coming back at each login.
  useEffect(() => {
    if (!ready || hidden) return;

    if (isOwnerOrAdmin) {
      const checklist = query.data;
      if (!slug || !checklist || checklist.finished) return;
      if (checklistSnoozed(slug)) return;
      queueMicrotask(() => setChecklistOpen(true));
      return;
    }

    if (!tourDone) queueMicrotask(() => setTourOpen(true));
  }, [hidden, isOwnerOrAdmin, query.data, ready, slug, tourDone]);

  useEffect(() => {
    const openTour = () => setTourOpen(true);
    const openChecklist = () => setChecklistOpen(true);
    window.addEventListener(OPEN_TOUR_EVENT, openTour);
    window.addEventListener(OPEN_CHECKLIST_EVENT, openChecklist);
    return () => {
      window.removeEventListener(OPEN_TOUR_EVENT, openTour);
      window.removeEventListener(OPEN_CHECKLIST_EVENT, openChecklist);
    };
  }, []);

  const closeChecklistForSession = useCallback(() => {
    if (slug) snoozeChecklist(slug);
    setChecklistOpen(false);
  }, [slug]);

  function finishTour() {
    setFinishedNow((current) => [...current, audience]);
    if (tokens?.access_token) void completeProductTour(tokens.access_token, audience).catch(() => undefined);
    setTourOpen(false);
    if (isOwnerOrAdmin) mutation.mutate({ action: "tour_completed" });
  }

  if (!ready) return null;

  return (
    <>
      {checklistOpen && isOwnerOrAdmin && query.data ? (
        <AdminChecklistDialog
          checklist={query.data}
          slug={slug}
          busy={mutation.isPending}
          onAction={(action, step) => mutation.mutate({ action, step })}
          onLater={closeChecklistForSession}
          onTour={() => {
            closeChecklistForSession();
            setTourOpen(true);
          }}
          onInvite={() => {
            closeChecklistForSession();
            setInviteOpen(true);
          }}
        />
      ) : null}
      {tourOpen ? <ProductTour audience={audience} slug={slug} onClose={finishTour} /> : null}
      {inviteOpen ? <InviteClientsDialog onClose={() => setInviteOpen(false)} /> : null}
    </>
  );
}

function AdminChecklistDialog({
  checklist,
  slug,
  busy,
  onAction,
  onLater,
  onTour,
  onInvite,
}: {
  checklist: AdminOnboardingChecklist;
  slug: string | null;
  busy: boolean;
  onAction: (action: OnboardingAction, step?: OnboardingStepId) => void;
  onLater: () => void;
  onTour: () => void;
  onInvite: () => void;
}) {
  const t = useTranslations("Onboarding");
  const navParams = useNavigationParams();

  return (
    <Dialog
      onClose={onLater}
      eyebrow={
        <span className="flex items-center gap-2" style={{ color: "var(--warning)" }}>
          <span aria-hidden="true">⚠</span>
          {t("popupEyebrow")}
        </span>
      }
      title={t(checklist.audience === "coach" ? "popupTitleCoach" : "popupTitle")}
      titleId="onboarding-title"
      description={<span className="leading-6">{t(checklist.audience === "coach" ? "popupIntroCoach" : "popupIntro", navParams)}</span>}
      size="lg"
      panelStyle={{ borderColor: "color-mix(in srgb, var(--warning) 45%, var(--border))" }}
      footer={
          <button type="button" onClick={onLater} className="rounded-xl px-4 py-2 text-sm font-semibold" style={{ background: "var(--text)", color: "var(--bg)" }}>
            {t("later")}
          </button>
      }
    >
        <div>
          <ChecklistView checklist={checklist} slug={slug} busy={busy} onAction={onAction} onNavigate={onLater} onTour={onTour} onInvite={onInvite} />
        </div>
    </Dialog>
  );
}

function ChecklistView({
  checklist,
  slug,
  busy,
  onAction,
  onNavigate,
  onSamePage,
  onTour,
  onInvite,
}: {
  checklist: AdminOnboardingChecklist;
  slug: string | null;
  busy: boolean;
  onAction: (action: OnboardingAction, step?: OnboardingStepId) => void;
  onNavigate?: () => void;
  /** A step links to the page that is already open: show that page instead of navigating. */
  onSamePage?: (hash: string | null) => void;
  onTour: () => void;
  onInvite: () => void;
}) {
  const t = useTranslations("Onboarding");
  const percent = Math.round((checklist.completed_count / Math.max(checklist.total, 1)) * 100);
  const nextStep = checklist.steps.find((step) => !step.done && !step.skipped)?.id;
  const teamHref = useTeamClubHref(checklist.steps.some((step) => step.id === "team"));
  const pathname = usePathname();

  return (
    <div>
      <div className="flex items-center justify-between text-xs font-semibold" style={{ color: "var(--muted)" }}>
        <span>{t("progress", { done: checklist.completed_count, total: checklist.total })}</span>
        <span>{percent}%</span>
      </div>
      <div
        className="mt-1.5 h-2 overflow-hidden rounded-full"
        style={{ background: "var(--panel-muted, var(--bg))" }}
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={checklist.total}
        aria-valuenow={checklist.completed_count}
        aria-label={t("progress", { done: checklist.completed_count, total: checklist.total })}
      >
        <div className="h-full rounded-full transition-all" style={{ width: `${percent}%`, background: "var(--success, var(--primary))" }} />
      </div>

      {checklist.finished ? <p className="mt-4 text-sm font-semibold" style={{ color: "var(--success, var(--primary))" }}>{t("allDone")}</p> : null}

      <ol className="mt-4 space-y-2">
        {checklist.steps.map((step, index) => {
          const open = !step.done && !step.skipped;
          const isNext = step.id === nextStep;
          const href = step.id === "team" ? teamHref : STEP_LINKS[step.id] ? adminHref(STEP_LINKS[step.id]!, slug) : undefined;
          const ctaStyle = isNext ? { background: "var(--primary)", color: "var(--primary-contrast, var(--bg))" } : { border: "1px solid var(--border)", color: "var(--text)" };

          return (
            <li
              key={step.id}
              className="rounded-xl p-3"
              style={{ border: isNext ? "1.5px solid var(--primary)" : "1px solid var(--border)", background: open ? "transparent" : "color-mix(in srgb, var(--success) 6%, transparent)" }}
            >
              <div className="flex items-start gap-3">
                <span
                  aria-hidden="true"
                  className="mt-0.5 grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs font-bold"
                  style={step.done ? { background: "var(--success)", color: "var(--success-contrast)" } : { border: "1.5px solid var(--border-strong, var(--border))", color: "var(--muted)" }}
                >
                  {step.done ? "✓" : index + 1}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold" style={{ color: "var(--text)", textDecoration: step.skipped ? "line-through" : undefined }}>
                    {t(`steps.${step.id}.title`)}
                    <span className="sr-only">
                      {" "}
                      {step.done ? t("statusDone") : step.skipped ? t("statusSkipped") : t("statusOpen")}
                    </span>
                  </p>
                  <p className="mt-0.5 text-xs leading-5" style={{ color: "var(--muted)" }}>
                    {step.done && step.auto ? t("doneAuto") : t(`steps.${step.id}.body`)}
                  </p>
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    {open ? (
                      <>
                        {step.id === "invite" ? (
                          <button type="button" onClick={onInvite} className="inline-flex rounded-lg px-3 py-1.5 text-xs font-semibold" style={ctaStyle}>{t(`steps.${step.id}.cta`)}</button>
                        ) : step.id === "tour" ? (
                          <button type="button" onClick={onTour} className="inline-flex rounded-lg px-3 py-1.5 text-xs font-semibold" style={ctaStyle}>{t(`steps.${step.id}.cta`)}</button>
                        ) : href ? (
                          <Link
                            href={href}
                            onClick={(event) => {
                              enterStaffView();
                              onNavigate?.();
                              const target = new URL(href, window.location.href);
                              if (target.pathname !== pathname || target.search !== window.location.search) return;
                              // Already on that page (the popup over it, or the
                              // Settings panel): a same-URL navigation does
                              // nothing visible, so show the page ourselves.
                              event.preventDefault();
                              const hash = target.hash ? target.hash.slice(1) : null;
                              if (onSamePage) onSamePage(hash);
                              else showOnPage(hash, null);
                            }}
                            className="inline-flex rounded-lg px-3 py-1.5 text-xs font-semibold" style={ctaStyle}>
                            {t(`steps.${step.id}.cta`)}
                          </Link>
                        ) : null}
                        <button type="button" disabled={busy} onClick={() => onAction("complete", step.id)} className="text-xs font-semibold underline disabled:opacity-50" style={{ color: "var(--muted)" }}>
                          {t("markDone")}
                        </button>
                        {/* ADR-176: the gym's time zone must be set, so it cannot be skipped. */}
                        {step.id === "timezone" ? null : (
                          <button type="button" disabled={busy} onClick={() => onAction("skip", step.id)} className="text-xs font-semibold underline disabled:opacity-50" style={{ color: "var(--muted)" }}>
                            {t("skip")}
                          </button>
                        )}
                      </>
                    ) : step.auto ? null : (
                      <button type="button" disabled={busy} onClick={() => onAction("reopen", step.id)} className="text-xs font-semibold underline disabled:opacity-50" style={{ color: "var(--muted)" }}>
                        {step.skipped ? t("unskip") : t("reopen")}
                      </button>
                    )}
                  </div>
                </div>
              </div>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

/**
 * Shows the page a step links to when it is already open: its `hash` section,
 * else what follows `after` (the Settings checklist), else the page top. Runs
 * after the next paint so a checklist that just collapsed has its new height.
 */
function showOnPage(hash: string | null, after: HTMLElement | null) {
  window.requestAnimationFrame(() => {
    const section = hash ? document.getElementById(hash) : null;
    if (hash && section) window.history.replaceState(window.history.state, "", `#${hash}`);
    const target = section ?? (after?.nextElementSibling as HTMLElement | null);
    if (target) target.scrollIntoView({ block: "start" });
    else window.scrollTo({ top: 0 });
  });
}

/** Utility → App configuration: the same checklist, always available. */
export function AdminOnboardingPanel() {
  const t = useTranslations("Onboarding");
  const { membershipRole } = useSelectedMembershipRole();
  const isOwnerOrAdmin = membershipRole === "owner" || membershipRole === "admin";
  const { query, mutation, slug } = useAdminOnboarding(isOwnerOrAdmin);
  const [inviteOpen, setInviteOpen] = useState(false);
  // Collapsed by default: open, it fills the settings page, and a step that
  // links here (e.g. «Open settings») looked like it did nothing.
  const [collapsed, setCollapsed] = useState(true);
  const panelRef = useRef<HTMLElement>(null);
  const checklist = query.data;

  if (!isOwnerOrAdmin || !checklist) return null;
  // Unfinished setup stands out in Spark (lib/spark.ts) so it is not missed.
  const pending = !checklist.finished;
  const textColor = pending ? "var(--spark-contrast)" : "var(--text)";
  const softColor = pending ? "var(--spark-contrast)" : "var(--muted)";

  return (
    <section
      ref={panelRef}
      id="setup-checklist"
      data-pending={pending ? "true" : undefined}
      className="rounded-[2rem] p-5"
      style={pending ? { background: "var(--spark)", border: "1px solid var(--spark)" } : { background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold" style={{ color: textColor }}>{t("panelTitle")}</h2>
          <p className="mt-1 max-w-2xl text-sm leading-6" style={{ color: softColor }}>
            {checklist.finished ? t("allDone") : (
              <>
                <strong>{t("progress", { done: checklist.completed_count, total: checklist.total })}</strong> · {t("panelIntro")}
              </>
            )}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={openProductTour} className="rounded-xl px-3 py-2 text-sm font-semibold" style={{ border: `1px solid ${pending ? "var(--spark-contrast)" : "var(--border)"}`, color: textColor }}>
            {t("takeTour")}
          </button>
          <button
            type="button"
            onClick={() => setCollapsed(!collapsed)}
            aria-expanded={!collapsed}
            aria-controls="setup-checklist-steps"
            className="rounded-xl px-3 py-2 text-sm font-semibold"
            style={pending ? { background: "var(--spark-contrast)", color: "var(--spark)" } : { color: "var(--muted)" }}
          >
            {collapsed ? t("showSteps") : t("hideSteps")}
          </button>
        </div>
      </div>
      {!collapsed ? (
        <div id="setup-checklist-steps" className="mt-4 rounded-2xl p-4" style={{ background: "var(--panel)" }}>
          <ChecklistView
            checklist={checklist}
            slug={slug}
            busy={mutation.isPending}
            onAction={(action, step) => mutation.mutate({ action, step })}
            onSamePage={(hash) => {
              // «Open settings» while on Settings: fold the steps away and
              // show the settings below them, as a fresh visit would.
              setCollapsed(true);
              showOnPage(hash, panelRef.current);
            }}
            onTour={openProductTour}
            onInvite={() => setInviteOpen(true)}
          />
        </div>
      ) : null}
      {inviteOpen ? <InviteClientsDialog onClose={() => setInviteOpen(false)} /> : null}
    </section>
  );
}

export function ProductTour({ audience, slug, onClose }: { audience: TourAudience; slug: string | null; onClose: () => void }) {
  const t = useTranslations("Onboarding");
  const navParams = useNavigationParams();
  const router = useRouter();
  const steps = TOUR_STEPS[audience];
  const [index, setIndex] = useState(0);
  const step = steps[index]!;
  const last = index === steps.length - 1;
  const href = step.href ? (audience === "admin" ? adminHref(step.href, slug) : step.href) : null;

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "ArrowRight") setIndex((current) => Math.min(current + 1, steps.length - 1));
      if (event.key === "ArrowLeft") setIndex((current) => Math.max(current - 1, 0));
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [steps.length]);

  return (
    <Dialog
      onClose={onClose}
      bare
      labelledBy="tour-step-title"
      size="md"
      panelClassName="overflow-y-auto p-6"
    >
        <div className="flex items-center justify-between">
          <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }} aria-live="polite">
            {t("tour.stepOf", { current: index + 1, total: steps.length })}
          </p>
          <button type="button" onClick={onClose} className="text-xs font-semibold underline" style={{ color: "var(--muted)" }}>
            {t("tour.skip")}
          </button>
        </div>
        <div className="mt-5 grid h-20 w-20 place-items-center rounded-3xl text-4xl" aria-hidden="true" style={{ background: "color-mix(in srgb, var(--primary) 14%, transparent)" }}>
          {step.icon}
        </div>
        <h2 id="tour-step-title" className="mt-4 text-xl font-semibold" style={{ color: "var(--text)" }}>
          {t(`tour.${audience}.${step.id}.title`)}
        </h2>
        <p id="tour-step-body" className="mt-2 min-h-[3rem] text-sm leading-6" style={{ color: "var(--muted)" }}>
          {t(`tour.${audience}.${step.id}.body`, navParams)}
        </p>
        {href ? (
          <button
            type="button"
            onClick={() => {
              if (audience === "admin") enterStaffView();
              onClose();
              router.push(href);
            }}
            className="mt-3 text-sm font-semibold underline"
            style={{ color: "var(--primary)" }}
          >
            {t("tour.showMe")}
          </button>
        ) : null}
        <div className="mt-6 flex items-center justify-between gap-3">
          <div className="flex gap-1.5" aria-hidden="true">
            {steps.map((item, dot) => (
              <span key={item.id} className="h-2 rounded-full transition-all" style={{ width: dot === index ? "1.25rem" : "0.5rem", background: dot === index ? "var(--primary)" : "var(--border)" }} />
            ))}
          </div>
          <div className="flex gap-2">
            {index > 0 ? (
              <button type="button" onClick={() => setIndex(index - 1)} className="rounded-xl px-4 py-2 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
                {t("tour.back")}
              </button>
            ) : null}
            <button
              type="button"
              onClick={() => (last ? onClose() : setIndex(index + 1))}
              className="rounded-xl px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast, var(--bg))" }}
            >
              {last ? t("tour.done") : t("tour.next")}
            </button>
          </div>
        </div>
    </Dialog>
  );
}

/** For profile pages: replays the role's tour. */
export function ReplayTourButton() {
  const t = useTranslations("Onboarding");
  return (
    <button type="button" onClick={openProductTour} className="rounded-xl px-4 py-2 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
      {t("tour.replay")}
    </button>
  );
}

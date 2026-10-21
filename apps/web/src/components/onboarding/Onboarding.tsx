"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";

import {
  completeProductTour,
  fetchAdminOnboarding,
  updateAdminOnboarding,
  type AdminOnboardingChecklist,
  type OnboardingAction,
  type OnboardingStepId,
} from "@/api/onboarding";
import { InviteClientsDialog } from "@/components/invites/InviteClients";
import { useSession } from "@/components/session-provider";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { TOUR_STEPS, checklistLaterKey, readStorage, writeStorage, type TourAudience } from "@/lib/onboarding";

const OPEN_TOUR_EVENT = "palee:open-tour";
const OPEN_CHECKLIST_EVENT = "palee:open-onboarding";
const HIDDEN_PATHS = /^\/(?:login|register|set-admin|join)(?:\/|$)/;

const STEP_LINKS: Partial<Record<OnboardingStepId, string>> = {
  settings: "/admin/settings",
  classes: "/admin/class-schedule",
  packages: "/admin/finance/packages",
  workout: "/admin/workouts/new",
  // ADR-170: an independent coach's practice.
  profile: "/admin/public-page",
  sessions: "/admin/appointments",
  team: "/clubs",
  bootcamp: "/admin/community?tab=events",
};

/** Lets any button (profile, settings) replay the tour for the current role. */
export function openProductTour() {
  window.dispatchEvent(new Event(OPEN_TOUR_EVENT));
}

export function openOnboardingChecklist() {
  window.dispatchEvent(new Event(OPEN_CHECKLIST_EVENT));
}

/** Real navigation labels, so instructions always match what users see. */
function useNavigationParams() {
  const nav = useTranslations("Navigation");
  return {
    path: `${nav("utility")} → ${nav("appConfigurations")}`,
    schedule: nav("schedule"),
    myWorkouts: nav("myWorkouts"),
    pantheon: nav("pantheon"),
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
 * popup until they finish or dismiss it; every role gets the product tour on
 * its first visit.
 */
export function OnboardingHost() {
  const pathname = usePathname();
  const { status, currentUser, tokens } = useSession();
  const { membershipRole, isLoading } = useSelectedMembershipRole();
  const ready = status === "authenticated" && Boolean(currentUser) && !currentUser?.vendor && !isLoading && Boolean(membershipRole);
  const isOwnerOrAdmin = membershipRole === "owner" || membershipRole === "admin";
  const audience: TourAudience = membershipRole === "athlete" ? "athlete" : membershipRole === "member" ? "member" : "admin";
  const { query, mutation, slug } = useAdminOnboarding(ready && isOwnerOrAdmin);
  const [tourOpen, setTourOpen] = useState(false);
  const [checklistOpen, setChecklistOpen] = useState(false);
  const [inviteOpen, setInviteOpen] = useState(false);
  const laterKey = checklistLaterKey(slug ?? "");
  // Completed tours live on the account (/auth/me), so a tour seen on one
  // device is not shown again on another. `finishedNow` covers this session.
  const [finishedNow, setFinishedNow] = useState<TourAudience[]>([]);
  const tourDone = Boolean(currentUser?.completed_tours?.includes(audience)) || finishedNow.includes(audience);
  const hidden = HIDDEN_PATHS.test(pathname);

  // First visit: admins see the checklist popup, clients see the tour.
  useEffect(() => {
    if (!ready || hidden) return;

    if (isOwnerOrAdmin) {
      const checklist = query.data;
      if (!checklist || checklist.dismissed || checklist.finished) return;
      if (readStorage("session", laterKey)) return;
      queueMicrotask(() => setChecklistOpen(true));
      return;
    }

    if (!tourDone) queueMicrotask(() => setTourOpen(true));
  }, [hidden, isOwnerOrAdmin, laterKey, query.data, ready, tourDone]);

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
    writeStorage("session", laterKey, "1");
    setChecklistOpen(false);
  }, [laterKey]);

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
          onDismiss={() => {
            mutation.mutate({ action: "dismiss" });
            setChecklistOpen(false);
          }}
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
  onDismiss,
  onTour,
  onInvite,
}: {
  checklist: AdminOnboardingChecklist;
  slug: string | null;
  busy: boolean;
  onAction: (action: OnboardingAction, step?: OnboardingStepId) => void;
  onLater: () => void;
  onDismiss: () => void;
  onTour: () => void;
  onInvite: () => void;
}) {
  const t = useTranslations("Onboarding");
  const navParams = useNavigationParams();
  const dialogRef = useModalFocusTrap<HTMLDivElement>(onLater);

  return (
    <div className="fixed inset-0 z-[65] flex items-end justify-center sm:items-center sm:p-4" style={{ background: "var(--scrim)" }} role="presentation" onClick={onLater}>
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="onboarding-title"
        aria-describedby="onboarding-intro"
        tabIndex={-1}
        onClick={(event) => event.stopPropagation()}
        className="max-h-[92dvh] w-full max-w-lg overflow-y-auto rounded-t-[1.6rem] p-5 sm:rounded-[1.6rem] sm:p-6"
        style={{ background: "var(--panel)", border: "1px solid color-mix(in srgb, var(--warning) 45%, var(--border))" }}
      >
        <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--warning)" }}>
          <span aria-hidden="true">⚠</span>
          {t("popupEyebrow")}
        </p>
        <h2 id="onboarding-title" className="mt-2 text-xl font-semibold" style={{ color: "var(--text)" }}>{t(checklist.audience === "coach" ? "popupTitleCoach" : "popupTitle")}</h2>
        <p id="onboarding-intro" className="mt-1 text-sm leading-6" style={{ color: "var(--muted)" }}>{t(checklist.audience === "coach" ? "popupIntroCoach" : "popupIntro", navParams)}</p>
        <div className="mt-4">
          <ChecklistView checklist={checklist} slug={slug} busy={busy} onAction={onAction} onNavigate={onLater} onTour={onTour} onInvite={onInvite} />
        </div>
        <div className="sticky bottom-0 -mx-5 -mb-5 mt-5 flex flex-col-reverse gap-2 px-5 pb-5 pt-3 sm:static sm:m-0 sm:mt-5 sm:flex-row sm:justify-between sm:p-0" style={{ background: "var(--panel)" }}>
          <button type="button" onClick={onDismiss} className="rounded-xl px-4 py-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {t("dontShow")}
          </button>
          <button type="button" onClick={onLater} className="rounded-xl px-4 py-2 text-sm font-semibold" style={{ background: "var(--text)", color: "var(--bg)" }}>
            {t("later")}
          </button>
        </div>
      </div>
    </div>
  );
}

function ChecklistView({
  checklist,
  slug,
  busy,
  onAction,
  onNavigate,
  onTour,
  onInvite,
}: {
  checklist: AdminOnboardingChecklist;
  slug: string | null;
  busy: boolean;
  onAction: (action: OnboardingAction, step?: OnboardingStepId) => void;
  onNavigate?: () => void;
  onTour: () => void;
  onInvite: () => void;
}) {
  const t = useTranslations("Onboarding");
  const percent = Math.round((checklist.completed_count / Math.max(checklist.total, 1)) * 100);
  const nextStep = checklist.steps.find((step) => !step.done && !step.skipped)?.id;

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
          const href = STEP_LINKS[step.id];
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
                          <Link href={adminHref(href, slug)} onClick={onNavigate} className="inline-flex rounded-lg px-3 py-1.5 text-xs font-semibold" style={ctaStyle}>
                            {t(`steps.${step.id}.cta`)}
                          </Link>
                        ) : null}
                        <button type="button" disabled={busy} onClick={() => onAction("complete", step.id)} className="text-xs font-semibold underline disabled:opacity-50" style={{ color: "var(--muted)" }}>
                          {t("markDone")}
                        </button>
                        <button type="button" disabled={busy} onClick={() => onAction("skip", step.id)} className="text-xs font-semibold underline disabled:opacity-50" style={{ color: "var(--muted)" }}>
                          {t("skip")}
                        </button>
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

/** Utility → App configuration: the same checklist, always available. */
export function AdminOnboardingPanel() {
  const t = useTranslations("Onboarding");
  const { membershipRole } = useSelectedMembershipRole();
  const isOwnerOrAdmin = membershipRole === "owner" || membershipRole === "admin";
  const { query, mutation, slug } = useAdminOnboarding(isOwnerOrAdmin);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [collapsed, setCollapsed] = useState<boolean | null>(null);
  const checklist = query.data;

  if (!isOwnerOrAdmin || !checklist) return null;
  const isCollapsed = collapsed ?? checklist.finished;

  return (
    <section id="setup-checklist" className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("panelTitle")}</h2>
          <p className="mt-1 max-w-2xl text-sm leading-6" style={{ color: "var(--muted)" }}>
            {checklist.finished ? t("allDone") : t("panelIntro")}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={openProductTour} className="rounded-xl px-3 py-2 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
            {t("takeTour")}
          </button>
          {checklist.dismissed ? (
            <button type="button" disabled={mutation.isPending} onClick={() => mutation.mutate({ action: "restore" })} className="rounded-xl px-3 py-2 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
              {t("showPopupAgain")}
            </button>
          ) : null}
          <button type="button" onClick={() => setCollapsed(!isCollapsed)} aria-expanded={!isCollapsed} className="rounded-xl px-3 py-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {isCollapsed ? t("showSteps") : t("hideSteps")}
          </button>
        </div>
      </div>
      {!isCollapsed ? (
        <div className="mt-4">
          <ChecklistView
            checklist={checklist}
            slug={slug}
            busy={mutation.isPending}
            onAction={(action, step) => mutation.mutate({ action, step })}
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
  const dialogRef = useModalFocusTrap<HTMLDivElement>(onClose);
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
    <div className="fixed inset-0 z-[75] flex items-end justify-center sm:items-center sm:p-4" style={{ background: "var(--scrim)" }} role="presentation">
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-roledescription={t("tour.roleDescription")}
        aria-labelledby="tour-step-title"
        aria-describedby="tour-step-body"
        tabIndex={-1}
        className="w-full max-w-md rounded-t-[1.6rem] p-6 sm:rounded-[1.6rem]"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
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
      </div>
    </div>
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

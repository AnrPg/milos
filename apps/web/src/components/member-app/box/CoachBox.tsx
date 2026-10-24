"use client";

import Link from "next/link";
import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchMyAppointments } from "@/api/appointments";
import type { EffectiveEntitlement } from "@/api/my-finance";
import { allowanceRemaining, hasCapability, hasFeature } from "@/components/client/entitlement";
import { HubActionTile, HubButton, HubCard, HubIcons } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { nextAppointment } from "@/lib/solo-coach";
import { dateKeyInZone, formatInZone, zonedText } from "@/lib/zoned-time";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { YourTime } from "@/components/zoned-time";
import { inboxHref } from "@/components/chat/inbox/inbox-model";

/** Shared with `Box › Ραντεβού`, so booking there refreshes this card. */
const MY_APPOINTMENTS_KEY = ["me", "appointments", "mine"] as const;

const leafIcon = (
  <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M5 19c0-8 5-13 14-14-1 9-6 14-14 14Z" />
    <path d="M5 19 13 11" />
  </svg>
);

/**
 * An independent coach's Box actions (vision §7.10): Συνεδρίες · Βίντεο ·
 * Διατροφή · Μηνύματα. Each shows only when the client's package includes
 * it; messages always do.
 */
export function CoachActions({ entitlement }: { entitlement: EffectiveEntitlement | null | undefined }) {
  const t = useTranslations("SoloCoach");
  const tApp = useTranslations("MemberApp");
  const actions = [
    { href: "/box/appointments", label: t("box.sessions"), icon: HubIcons.clock, shown: hasFeature(entitlement, "appointments") },
    { href: "/box/videos", label: tApp("actionVideos"), icon: HubIcons.video, shown: hasFeature(entitlement, "videos") },
    { href: "/box/coach", label: t("box.nutrition"), icon: leafIcon, shown: hasCapability(entitlement, "receive_nutrition_plan") },
    { href: inboxHref({ filter: "coach" }), label: t("box.messages"), icon: HubIcons.chat, shown: true },
  ].filter((action) => action.shown);

  return (
    <nav aria-label={t("box.actionsLabel")} className="grid gap-2" style={{ gridTemplateColumns: `repeat(${actions.length}, minmax(0, 1fr))` }}>
      {actions.map((action) => (
        <HubActionTile key={action.href} href={action.href} label={action.label} icon={action.icon} />
      ))}
    </nav>
  );
}

/** «Επόμενη συνεδρία»: when, in person or online (with the call link), and the way to book. */
export function NextCoachSession() {
  const t = useTranslations("SoloCoach");
  const tApp = useTranslations("MemberApp");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const now = useMemo(() => new Date(), []);
  const practiceZone = useOrganizationTimeZone();
  const appointments = useQuery({
    queryKey: MY_APPOINTMENTS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchMyAppointments(token!),
    staleTime: 60_000,
  });
  const next = nextAppointment(appointments.data ?? [], now);

  return (
    <HubCard eyebrow={tApp("nextSession")}>
      {appointments.isPending && token ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{tApp("loading")}</p>
      ) : next ? (
        <div className="flex flex-col gap-3">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="truncate text-lg font-extrabold" style={{ color: "var(--text)" }}>
                {sessionWhen(next.slot.starts_at, now, locale, tApp("todayLabel"), practiceZone)}
                <YourTime at={next.slot.starts_at} zone={practiceZone} format="day-time" />
              </p>
              <p className="truncate text-sm" style={{ color: "var(--dim)" }}>
                {[
                  next.slot.kind === "assessment" ? t("box.assessment") : t("box.ptSession"),
                  next.slot.mode === "online" ? t("box.online") : t("box.inPerson"),
                  next.slot.duration_minutes ? t("box.minutes", { minutes: next.slot.duration_minutes }) : null,
                ]
                  .filter(Boolean)
                  .join(" · ")}
              </p>
            </div>
          </div>
          <div className="flex gap-2">
            {next.slot.mode === "online" && next.slot.meeting_url ? (
              <a
                href={next.slot.meeting_url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {t("box.join")}
              </a>
            ) : null}
            <Link
              href="/box/appointments"
              className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
              style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
            >
              {t("box.manage")}
            </Link>
          </div>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("box.noSession")}</p>
          <HubButton href="/box/appointments">{t("box.bookSession")}</HubButton>
        </div>
      )}
    </HubCard>
  );
}

/** The session package (vision §7.10): sessions left, or a nudge when there is none. */
export function SessionPackageSummary({ entitlement }: { entitlement: EffectiveEntitlement | null | undefined }) {
  const t = useTranslations("SoloCoach");
  const sessions = allowanceRemaining(entitlement, "pt_sessions");
  if (!entitlement?.plan) return <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("box.noPackage")}</p>;
  if (!sessions) return null;

  return (
    <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
      {sessions.remaining === "unlimited" || sessions.limit === "unlimited"
        ? t("box.sessionsUnlimited")
        : t("box.sessionsLeft", { remaining: sessions.remaining, limit: sessions.limit })}
    </p>
  );
}

// ADR-179: on the practice's clock (the coach's zone), its city added when the client's differs.
function sessionWhen(iso: string, now: Date, locale: string, todayLabel: string, zone: string | null = null) {
  const time = zonedText(iso, zone, locale, "time");
  return dateKeyInZone(iso, zone) === dateKeyInZone(now, zone)
    ? `${todayLabel} ${time}`
    : `${formatInZone(iso, zone, locale, { weekday: "long", day: "numeric", month: "short" })} ${time}`;
}

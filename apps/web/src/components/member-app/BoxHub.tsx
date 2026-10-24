"use client";

import { useTranslations } from "next-intl";
import { Suspense } from "react";

import type { OrganizationMembership } from "@/api/organizations";
import { entitledFeatures } from "@/components/client/entitlement";
import { useClientEntitlement } from "@/components/client/use-client-entitlement";
import { AnnouncementsCard } from "@/components/community/AnnouncementsCard";
import { gymClubFor } from "@/components/community/community";
import { useMyClubs } from "@/components/community/use-community";
import { AccessNotice, EntitlementCard } from "@/components/finance/MembershipEntitlement";
import { BoxToday } from "@/components/member-app/box/BoxToday";
import { boxExtensionsFor } from "@/components/member-app/box/box-extensions";
import { CoachActions, NextCoachSession, SessionPackageSummary } from "@/components/member-app/box/CoachBox";
import { HubActionTile, HubButton, HubCard, HubIcons, HubPage } from "@/components/member-app/HubParts";
import { ProviderTitle } from "@/components/providers/ProviderSwitcher";
import { TodayAcrossCard } from "@/components/providers/TodayAcrossCard";
import { SeasonsEntry } from "@/components/seasons/MySeasons";
import { useHasBillingProviders } from "@/lib/billing-providers";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { boxLayoutFor, boxTitle, type BoxLayout } from "@/lib/solo-coach";

/**
 * Box (brief §6.1, §7.4, mockup 08): "where and with whom do I train?".
 * Fixed order: «Σήμερα» across providers (ADR-162, only with more than one)
 * · today's workout · next booking · actions · membership (with «Φέρε φίλο»,
 * ADR-156, and the provider's seasons, ADR-167) · extensions (PT squads ADR-168, ADR-170) · announcements (the gym club's
 * #ανακοινώσεις, ADR-138). The title ▾ switches provider (board 17 Q1);
 * everything below it is that provider's.
 *
 * An independent coach (ADR-170, vision §7.10) gets the same layout in the
 * coach's words: «Νίκος Π. · Personal coach ▾», the next session instead of
 * the next class, Συνεδρίες · Βίντεο · Διατροφή · Μηνύματα, and the session
 * package; announcements come from the coach's «Team» club.
 *
 * Without a membership at any box or coach the cards mean nothing, so Box
 * shows only «Βρες box» (ANR 2026-10-24).
 */
export function BoxHub() {
  const t = useTranslations("MemberApp");
  const tProviders = useTranslations("Providers");
  const tCoach = useTranslations("SoloCoach");
  const { membership, memberships, isLoading } = useSelectedMembershipRole();
  const { hasBillingProviders } = useHasBillingProviders();
  const { entitlement } = useClientEntitlement();
  const clubs = useMyClubs();
  const gymClub = gymClubFor(clubs.data ?? [], membership?.organization.id);
  const layout = boxLayoutFor(membership?.organization.provider_kind);
  const name = membership?.settings?.brand_name?.trim() || membership?.organization.name || t("boxTitle");
  const title = boxTitle(name, layout, tProviders("kind.coach"));

  if (isLoading) return <HubPage title={t("boxTitle")}>{null}</HubPage>;
  if (memberships.length === 0) return <FindABox />;

  return (
    <HubPage title={<ProviderTitle title={title} />}>
      <TodayAcrossCard />
      {layout === "coach" ? (
        <>
          <BoxToday
            nextSession={<NextCoachSession />}
            emptyAction={{ href: "/box/appointments", label: tCoach("box.bookSession") }}
          />
          <CoachActions entitlement={entitlement} />
        </>
      ) : (
        <>
          <BoxToday />
          <GymActions entitlement={entitlement} />
        </>
      )}

      <HubCard eyebrow={layout === "coach" ? tCoach("box.package") : t("membership")}>
        <div className="mb-4 flex flex-col gap-3">
          <AccessNotice entitlement={entitlement} />
          {layout === "coach" ? <SessionPackageSummary entitlement={entitlement} /> : null}
          {entitlement?.plan ? (
            <EntitlementCard entitlement={entitlement} />
          ) : layout === "gym" ? (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("membershipNone")}</p>
          ) : null}
          <Suspense fallback={null}>
            <SeasonsEntry />
          </Suspense>
        </div>
        <div className="flex gap-2">
          {hasBillingProviders ? (
            <HubButton href={membership ? `/me/payments?box=${encodeURIComponent(membership.organization.slug)}` : "/me/payments"}>
              {t("membershipOpen")}
            </HubButton>
          ) : null}
          {membership ? (
            <HubButton href={`/me/referrals?box=${encodeURIComponent(membership.organization.slug)}`}>{t("membershipReferral")}</HubButton>
          ) : null}
        </div>
      </HubCard>

      {membership ? <BoxExtensions membership={membership} layout={layout} /> : null}

      {gymClub ? <AnnouncementsCard club={gymClub} /> : null}
    </HubPage>
  );
}

/** Box for someone who is not in any box or with any coach yet. */
function FindABox() {
  const t = useTranslations("MemberApp");
  return (
    <HubPage title={t("boxTitle")}>
      <HubCard>
        <h2 className="text-lg font-bold" style={{ color: "var(--text)" }}>{t("boxFindTitle")}</h2>
        <p className="mb-4 mt-1 text-sm" style={{ color: "var(--text-soft)" }}>{t("boxFindBody")}</p>
        <HubButton href="/around/boxes" primary>{t("boxFindAction")}</HubButton>
      </HubCard>
    </HubPage>
  );
}

function GymActions({ entitlement }: { entitlement: ReturnType<typeof useClientEntitlement>["entitlement"] }) {
  const t = useTranslations("MemberApp");
  const features = entitledFeatures(entitlement);
  const actions = [
    { href: "/box/schedule", label: t("actionSchedule"), icon: HubIcons.calendar, shown: true },
    { href: "/box/appointments", label: t("actionAppointments"), icon: HubIcons.clock, shown: features.includes("appointments") },
    { href: "/box/videos", label: t("actionVideos"), icon: HubIcons.video, shown: features.includes("videos") },
    { href: "/box/coach", label: t("actionCoach"), icon: HubIcons.chat, shown: features.includes("coaching") },
  ].filter((action) => action.shown);

  return (
    <nav aria-label={t("boxActions")} className="grid gap-2" style={{ gridTemplateColumns: `repeat(${actions.length}, minmax(0, 1fr))` }}>
      {actions.map((action) => (
        <HubActionTile key={action.href} href={action.href} label={action.label} icon={action.icon} />
      ))}
    </nav>
  );
}

/** Sections other features plug into Box (`box-extensions.tsx`). */
function BoxExtensions({ membership, layout }: { membership: OrganizationMembership; layout: BoxLayout }) {
  return (
    <>
      {boxExtensionsFor(layout).map(({ id, Component }) => (
        <Component key={id} membership={membership} providerKind={layout} />
      ))}
    </>
  );
}

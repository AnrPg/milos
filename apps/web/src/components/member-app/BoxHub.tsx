"use client";

import { useTranslations } from "next-intl";

import { entitledFeatures } from "@/components/client/entitlement";
import { useClientEntitlement } from "@/components/client/use-client-entitlement";
import { AnnouncementsCard } from "@/components/community/AnnouncementsCard";
import { gymClubFor } from "@/components/community/community";
import { useMyClubs } from "@/components/community/use-community";
import { AccessNotice, EntitlementCard } from "@/components/finance/MembershipEntitlement";
import { BOX_EXTENSIONS } from "@/components/member-app/box/box-extensions";
import { BoxToday } from "@/components/member-app/box/BoxToday";
import { HubActionTile, HubButton, HubCard, HubIcons, HubPage } from "@/components/member-app/HubParts";
import { ProviderTitle } from "@/components/providers/ProviderSwitcher";
import { TodayAcrossCard } from "@/components/providers/TodayAcrossCard";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * Box (brief §6.1, §7.4, mockup 08): "where and with whom do I train?".
 * Fixed order: «Σήμερα» across providers (ADR-162, only with more than one)
 * · today's workout · next booking · actions · membership (with «Φέρε φίλο»,
 * ADR-156) · extensions (PT squads, ADR-168) · announcements (the gym club's
 * #ανακοινώσεις, ADR-138). The title
 * ▾ switches provider (board 17 Q1); everything below it is that provider's.
 */
export function BoxHub() {
  const t = useTranslations("MemberApp");
  const { membership } = useSelectedMembershipRole();
  const { entitlement } = useClientEntitlement();
  const features = entitledFeatures(entitlement);
  const clubs = useMyClubs();
  const gymClub = gymClubFor(clubs.data ?? [], membership?.organization.id);
  const title = membership?.settings?.brand_name?.trim() || membership?.organization.name || t("boxTitle");
  const actions = [
    { href: "/box/schedule", label: t("actionSchedule"), icon: HubIcons.calendar, shown: true },
    { href: "/box/appointments", label: t("actionAppointments"), icon: HubIcons.clock, shown: features.includes("appointments") },
    { href: "/box/videos", label: t("actionVideos"), icon: HubIcons.video, shown: features.includes("videos") },
    { href: "/box/coach", label: t("actionCoach"), icon: HubIcons.chat, shown: features.includes("coaching") },
  ].filter((action) => action.shown);

  return (
    <HubPage title={<ProviderTitle title={title} />}>
      <TodayAcrossCard />
      <BoxToday />

      <nav aria-label={t("boxActions")} className="grid gap-2" style={{ gridTemplateColumns: `repeat(${actions.length}, minmax(0, 1fr))` }}>
        {actions.map((action) => (
          <HubActionTile key={action.href} href={action.href} label={action.label} icon={action.icon} />
        ))}
      </nav>

      <HubCard eyebrow={t("membership")}>
        <div className="mb-4 flex flex-col gap-3">
          <AccessNotice entitlement={entitlement} />
          {entitlement?.plan ? (
            <EntitlementCard entitlement={entitlement} />
          ) : (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("membershipNone")}</p>
          )}
        </div>
        <div className="flex gap-2">
          <HubButton href="/me/payments">{t("membershipOpen")}</HubButton>
          {membership ? (
            <HubButton href={`/me/referrals?box=${encodeURIComponent(membership.organization.slug)}`}>{t("membershipReferral")}</HubButton>
          ) : null}
        </div>
      </HubCard>

      {BOX_EXTENSIONS.filter((extension) => extension.kinds.includes("gym")).map(({ id, Component }) => (
        <Component key={id} membership={membership} providerKind="gym" />
      ))}

      {gymClub ? <AnnouncementsCard club={gymClub} /> : null}
    </HubPage>
  );
}

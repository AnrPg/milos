"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";

import { AroundVisibilitySetting } from "@/components/around/AroundSettings";
import { BodyDefaultVisibilitySetting } from "@/components/body/BodyPreferenceSettings";
import { WellnessSummarySharing } from "@/components/buddy/WellnessSummarySharing";
import { BlockedPeople, PartnerVisibilitySetting } from "@/components/partners/PartnerSettings";
import { BackToMe } from "@/components/member-app/me/BackToMe";
import { InjurySharingSetting } from "@/components/member-app/wellbeing/InjurySharing";
import { LeaderboardSetting } from "@/components/member-app/me/LeaderboardSetting";
import { CommunityOptIns, EntryDefaultsSetting, ProfilePrsSetting } from "@/components/member-app/me/SharingSections";
import { PRSharingSettings } from "@/components/pantheon/PRSharingSettings";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { useSession } from "@/components/session-provider";
import { AccountPrivacySetting } from "@/components/social/AccountPrivacy";
import { BookingSharingSetting } from "@/components/social/BookingSharing";
import { MemberVisibilitySetting } from "@/components/social/MemberVisibility";
import { showsTenantSelfServiceSurfaces } from "@/lib/account-surfaces";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Εγώ › Κοινοποίηση & ορατότητα (brief §7.11, mockup «privacy», ADR-137):
 * everything that decides who sees what of me, in one place, grouped as the
 * mockup does (ADR-196): «Ο coach μου βλέπει» (PRs, the weekly wellness
 * summary of ADR-160, measurements; injuries per injury, ADR-286), «Κοινότητα»
 * (leaderboards, PR celebrations, challenges, Partners of ADR-280), the PRs on
 * my profile, PRs shared with accounts (ADR-129), the default for new entries
 * (ADR-139 §3), then the account and people-search switches of ADR-193 and
 * the people I blocked. Rest days moved to Ρυθμίσεις (ADR-196).
 */
export function SharingPage() {
  const t = useTranslations("MemberApp");
  const tBody = useTranslations("Body");
  const tBuddy = useTranslations("Buddy");
  const tPrSharing = useTranslations("PrSharing");
  const tSocial = useTranslations("Social");
  const tClubs = useTranslations("Clubs");
  const tAround = useTranslations("Around");
  const tPartners = useTranslations("Partners");
  const i18n = useUiTranslations();
  const { currentUser } = useSession();
  const selfService = showsTenantSelfServiceSurfaces(currentUser);
  useLegacySectionRedirects();

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-3xl space-y-4">
        <BackToMe />
        <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>{t("meSharing")}</h1>
        <CollapsibleSection id="coach-sees" title={t("sharing.coachSeesTitle")} description={t("sharing.coachSeesHint")} defaultOpen>
          <div className="space-y-6">
            <PRSharingSettings part="coach" />
            <div id="wellness-summary" className="space-y-2">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{tBuddy("sharingSectionTitle")}</p>
              <p className="text-xs" style={{ color: "var(--muted)" }}>{tBuddy("sharingSectionHint")}</p>
              <WellnessSummarySharing />
            </div>
            <div id="measurements" className="space-y-2">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{tBody("defaultVisibilityLabel")}</p>
              <BodyDefaultVisibilitySetting />
            </div>
            {/* ADR-286: injuries reach the boxes per injury; who read them. */}
            <InjurySharingSetting />
          </div>
        </CollapsibleSection>
        <CollapsibleSection id="community" title={t("sharing.communityTitle")} description={t("sharing.communityHint")} defaultOpen>
          <div className="space-y-6">
            {selfService ? (
              <div id="leaderboard" className="space-y-2">
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("leaderboard0381247")}</p>
                <LeaderboardSetting />
              </div>
            ) : null}
            <CommunityOptIns />
            <div id="partners" className="space-y-2">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{tPartners("settingsTitle")}</p>
              <p className="text-xs" style={{ color: "var(--muted)" }}>{tPartners("settingsHint")}</p>
              <PartnerVisibilitySetting />
            </div>
          </div>
        </CollapsibleSection>
        <CollapsibleSection id="profile-prs" title={t("sharing.profilePrsTitle")} description={t("sharing.profilePrsHint")} defaultOpen>
          <ProfilePrsSetting />
        </CollapsibleSection>
        <CollapsibleSection id="pr-sharing" title={tPrSharing("settingsTitle")} description={tPrSharing("settingsDescription")} defaultOpen>
          <PRSharingSettings part="grants" />
        </CollapsibleSection>
        <CollapsibleSection id="defaults" title={t("sharing.defaultsTitle")} description={t("sharing.defaultsHint")} defaultOpen>
          <EntryDefaultsSetting />
        </CollapsibleSection>
        <CollapsibleSection id="account-privacy" title={tSocial("privacyTitle")} description={tSocial("privacyHint")} defaultOpen>
          <AccountPrivacySetting />
        </CollapsibleSection>
        <CollapsibleSection id="bookings" title={tSocial("bookingSharingSectionTitle")} description={tSocial("bookingSharingSectionHint")} defaultOpen>
          <BookingSharingSetting />
        </CollapsibleSection>
        <CollapsibleSection id="members-list" title={tClubs("visibilityTitle")} description={tClubs("visibilityHint")} defaultOpen>
          <MemberVisibilitySetting />
        </CollapsibleSection>
        <CollapsibleSection id="around-visibility" title={tAround("visibilityTitle")} description={tAround("visibilityHint")} defaultOpen>
          <AroundVisibilitySetting />
        </CollapsibleSection>
        <CollapsibleSection id="blocked" title={tPartners("blockedTitle")} description={tPartners("blockedHint")}>
          <BlockedPeople />
        </CollapsibleSection>
      </div>
    </main>
  );
}

/** Rest days moved to Ρυθμίσεις (ADR-196); old links still land on them. */
function useLegacySectionRedirects() {
  const router = useRouter();
  useEffect(() => {
    const follow = () => {
      const target = LEGACY_SECTION_TARGETS[window.location.hash];
      if (target) router.replace(target);
    };
    follow();
    window.addEventListener("hashchange", follow);
    return () => window.removeEventListener("hashchange", follow);
  }, [router]);
}

const LEGACY_SECTION_TARGETS: Record<string, string> = {
  "#training-schedule": "/me/settings#training-schedule",
};

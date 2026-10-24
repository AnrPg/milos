"use client";

import { useTranslations } from "next-intl";

import { AroundVisibilitySetting } from "@/components/around/AroundSettings";
import { WellnessSummarySharing } from "@/components/buddy/WellnessSummarySharing";
import { BlockedPeople, PartnerVisibilitySetting } from "@/components/partners/PartnerSettings";
import { BackToMe } from "@/components/member-app/me/BackToMe";
import { LeaderboardSetting } from "@/components/member-app/me/LeaderboardSetting";
import { RestDaysSettings } from "@/components/member-app/me/RestDaysSettings";
import { PRSharingSettings } from "@/components/pantheon/PRSharingSettings";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { useSession } from "@/components/session-provider";
import { AccountPrivacySetting } from "@/components/social/AccountPrivacy";
import { BookingSharingSetting } from "@/components/social/BookingSharing";
import { MemberVisibilitySetting } from "@/components/social/MemberVisibility";
import { showsTenantSelfServiceSurfaces } from "@/lib/account-surfaces";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Εγώ › Κοινοποίηση & ορατότητα (brief §7.11, ADR-137): everything that
 * decides who sees what of me, in one place. ADR-139's default visibility for
 * new entries joins this page with the visibility ladder. ADR-160 adds the
 * coach's weekly wellness summary and who opened it; ADR-169 the Partners
 * switch and the people you blocked; ADR-193 the private account and the
 * people-search switches.
 */
export function SharingPage() {
  const t = useTranslations("MemberApp");
  const tPrSharing = useTranslations("PrSharing");
  const tSocial = useTranslations("Social");
  const tClubs = useTranslations("Clubs");
  const tAround = useTranslations("Around");
  const tBuddy = useTranslations("Buddy");
  const tPartners = useTranslations("Partners");
  const i18n = useUiTranslations();
  const { currentUser } = useSession();
  const selfService = showsTenantSelfServiceSurfaces(currentUser);

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-3xl space-y-4">
        <BackToMe />
        <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>{t("meSharing")}</h1>
        <CollapsibleSection id="pr-sharing" title={tPrSharing("settingsTitle")} description={tPrSharing("settingsDescription")} defaultOpen>
          <PRSharingSettings />
        </CollapsibleSection>
        <CollapsibleSection id="bookings" title={tSocial("bookingSharingSectionTitle")} description={tSocial("bookingSharingSectionHint")} defaultOpen>
          <BookingSharingSetting />
        </CollapsibleSection>
        <CollapsibleSection id="account-privacy" title={tSocial("privacyTitle")} description={tSocial("privacyHint")} defaultOpen>
          <AccountPrivacySetting />
        </CollapsibleSection>
        <CollapsibleSection id="members-list" title={tClubs("visibilityTitle")} description={tClubs("visibilityHint")} defaultOpen>
          <MemberVisibilitySetting />
        </CollapsibleSection>
        <CollapsibleSection id="around-visibility" title={tAround("visibilityTitle")} description={tAround("visibilityHint")} defaultOpen>
          <AroundVisibilitySetting />
        </CollapsibleSection>
        <CollapsibleSection id="wellness-summary" title={tBuddy("sharingSectionTitle")} description={tBuddy("sharingSectionHint")} defaultOpen>
          <WellnessSummarySharing />
        </CollapsibleSection>
        <CollapsibleSection id="partners" title={tPartners("settingsTitle")} description={tPartners("settingsHint")} defaultOpen>
          <PartnerVisibilitySetting />
        </CollapsibleSection>
        <CollapsibleSection id="blocked" title={tPartners("blockedTitle")} description={tPartners("blockedHint")}>
          <BlockedPeople />
        </CollapsibleSection>
        {selfService ? (
          <>
            <CollapsibleSection id="leaderboard" title={i18n("leaderboard0381247")} description={i18n("optInRanking04c1cd3")} defaultOpen>
              <LeaderboardSetting />
            </CollapsibleSection>
            <CollapsibleSection
              id="training-schedule"
              title={i18n("trainingSchedule80e51e2")}
              description={i18n("markYourWeeklyRestDaysUpTo5ee5b72a")}
              defaultOpen
            >
              <RestDaysSettings />
            </CollapsibleSection>
          </>
        ) : null}
      </div>
    </main>
  );
}

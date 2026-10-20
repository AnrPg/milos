"use client";

import { useTranslations } from "next-intl";

import { LeaderboardSetting } from "@/components/member-app/me/LeaderboardSetting";
import { RestDaysSettings } from "@/components/member-app/me/RestDaysSettings";
import { PRSharingSettings } from "@/components/pantheon/PRSharingSettings";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { useSession } from "@/components/session-provider";
import { BookingSharingSetting } from "@/components/social/BookingSharing";
import { showsTenantSelfServiceSurfaces } from "@/lib/account-surfaces";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Εγώ › Κοινοποίηση & ορατότητα (brief §7.11, ADR-137): everything that
 * decides who sees what of me, in one place. ADR-139's default visibility for
 * new entries joins this page with the visibility ladder.
 */
export function SharingPage() {
  const t = useTranslations("MemberApp");
  const tPrSharing = useTranslations("PrSharing");
  const tSocial = useTranslations("Social");
  const i18n = useUiTranslations();
  const { currentUser } = useSession();
  const selfService = showsTenantSelfServiceSurfaces(currentUser);

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-3xl space-y-4">
        <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>{t("meSharing")}</h1>
        <CollapsibleSection id="pr-sharing" title={tPrSharing("settingsTitle")} description={tPrSharing("settingsDescription")} defaultOpen>
          <PRSharingSettings />
        </CollapsibleSection>
        <CollapsibleSection id="bookings" title={tSocial("bookingSharingSectionTitle")} description={tSocial("bookingSharingSectionHint")} defaultOpen>
          <BookingSharingSetting />
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

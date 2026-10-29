"use client";

import Link from "next/link";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { CountBadge } from "@/components/buddy/BuddyBits";
import { inboxHref } from "@/components/chat/inbox/inbox-model";
import { HubCard, HubList, HubListRow, HubPage } from "@/components/member-app/HubParts";
import { BackToMe } from "@/components/member-app/me/BackToMe";
import { usePasswordResets } from "@/components/member-app/me/use-password-resets";
import { openOnboardingChecklist, openProductTour } from "@/components/onboarding/Onboarding";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref } from "@/lib/organization-slug";
import { ownsCoachPractice } from "@/lib/solo-coach";
import { clientExtraLinks } from "@/lib/role-navigation";

/** Where «Αναφορά προβλήματος» writes (the vendor's support inbox); a build can point it elsewhere. */
const SUPPORT_EMAIL = process.env.NEXT_PUBLIC_SUPPORT_EMAIL || "support@palee.app";

/**
 * Εγώ › Βοήθεια & ξενάγηση (vision §7.11, mockup «help», ADR-196): the
 * product tour and first steps, how visibility works, contacting the box,
 * reporting a problem, opening a coach practice (ADR-170), and for staff
 * their extra logs and the password resets they handle (ADR-187). The way
 * back to the console is its own Εγώ row, «Διαχείριση» (ADR-196 amended).
 */
export function HelpPage() {
  const t = useTranslations("MemberApp");
  const tNav = useTranslations("Navigation");
  const tGuides = useTranslations("Guides");
  const tCoach = useTranslations("SoloCoach");
  const tResets = useTranslations("passwordResets");
  const { membership, memberships, selectedOrganizationSlug } = useSelectedMembershipRole();
  const resets = usePasswordResets();
  const [visibilityOpen, setVisibilityOpen] = useState(false);
  const extras = clientExtraLinks(membership);

  return (
    <HubPage title={t("meHelp")} back={<BackToMe />}>
      <HubList>
        <HubListRow onClick={openProductTour} label={t("meTour")} />
        {/* ADR-193 (walkthroughs): every guide, started again from here. */}
        <HubListRow href="/guides" label={tGuides("ui.meRow")} detail={tGuides("ui.meRowHint")} />
        <HubListRow onClick={openOnboardingChecklist} label={t("meChecklist")} />
        <HubListRow onClick={() => setVisibilityOpen((open) => !open)} label={t("helpVisibility")} />
        {memberships.length > 0 ? (
          <HubListRow href={inboxHref({ filter: "clubs" })} label={t("helpContactBox")} detail={t("helpContactBoxHint")} />
        ) : null}
        {SUPPORT_EMAIL ? (
          <HubListRow href={`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent(t("helpReportSubject"))}`} label={t("helpReport")} />
        ) : null}
        {/* ADR-170: anyone can open a practice as an independent coach, once. */}
        {ownsCoachPractice(memberships) ? null : (
          <HubListRow href="/me/coach-practice" label={tCoach("me.row")} detail={tCoach("me.rowHint")} />
        )}
      </HubList>

      {visibilityOpen ? (
        <HubCard eyebrow={t("helpVisibility")}>
          <div className="flex flex-col gap-2 text-sm leading-6" style={{ color: "var(--text-soft)" }} data-testid="help-visibility">
            <p>{t("helpVisibilityPrivate")}</p>
            <p>{t("helpVisibilityCoach")}</p>
            <p>{t("helpVisibilityPosts")}</p>
            <Link href="/me/sharing" className="font-semibold" style={{ color: "var(--primary)" }}>
              {t("meSharing")} ›
            </Link>
          </div>
        </HubCard>
      ) : null}

      {extras.length > 0 || resets.shown ? (
        <HubCard eyebrow={t("helpStaffOnly")}>
          <div className="-mx-5 -mb-5 [&>*:first-child]:border-t-0">
            {extras.map((item) => (
              <HubListRow key={item.id} href={adminHref(item.href, selectedOrganizationSlug)} label={tNav(item.labelKey)} />
            ))}
            {resets.shown ? (
              <HubListRow
                href="/password-resets"
                label={tResets("navLink")}
                badge={resets.toAct > 0 ? <CountBadge count={resets.toAct} label={tResets("navLink")} /> : null}
              />
            ) : null}
          </div>
        </HubCard>
      ) : null}
    </HubPage>
  );
}

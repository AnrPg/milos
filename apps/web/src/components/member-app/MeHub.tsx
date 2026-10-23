"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";

import { openOnboardingChecklist, openProductTour } from "@/components/onboarding/Onboarding";
import { OrganizationSelector } from "@/components/organization-selector";
import { CountBadge } from "@/components/buddy/BuddyBits";
import { activeBuddies, recipientNames, unreadTotal } from "@/components/buddy/buddy-model";
import { useBuddies } from "@/components/buddy/use-buddies";
import { HubCard, HubList, HubListRow, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { useSocialSummary } from "@/components/social/use-social";
import { useHasBillingProviders } from "@/lib/billing-providers";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref } from "@/lib/organization-slug";
import { ownsBusiness, ownsCoachPractice } from "@/lib/solo-coach";
import { clientExtraLinks, hasStaffRole } from "@/lib/role-navigation";
import { setView } from "@/lib/view-mode";

/**
 * Εγώ (brief §6.1, §7.11, mockup 24): who I am to others, then a fixed list of
 * everything secondary, so the app needs no "More" drawer (brief §4.8).
 * Under the name, «ακόλουθοι · ακολουθείς» opens the connections screen
 * (plan §5a Q12).
 * «Φέρε φίλο» (ADR-156) leads the list as in the mockup, then Buddy για
 * στήριξη (ADR-160) with its unread messages; Συνδεδεμένες συσκευές (ADR-155)
 * follows.
 */
export function MeHub() {
  const t = useTranslations("MemberApp");
  const tBody = useTranslations("Body");
  const tFirstRun = useTranslations("FirstRun");
  const tNav = useTranslations("Navigation");
  const tSocial = useTranslations("Social");
  const tCheckIn = useTranslations("CheckIn");
  const tBuddy = useTranslations("Buddy");
  const tCoach = useTranslations("SoloCoach");
  const tBusiness = useTranslations("Business");
  const summary = useSocialSummary();
  const buddies = useBuddies();
  const buddyNames = recipientNames(activeBuddies(buddies.data), tBuddy("someone"));
  const buddyUnread = unreadTotal(buddies.data);
  const router = useRouter();
  const { currentUser, signOut } = useSession();
  const { membership, memberships, selectedOrganizationSlug } = useSelectedMembershipRole();
  const { hasBillingProviders } = useHasBillingProviders();
  const nickname = currentUser?.nickname ?? "";
  const initials = nickname.slice(0, 2).toUpperCase() || "?";
  const clubs = memberships.map((entry) => entry.settings?.brand_name?.trim() || entry.organization.name);
  const extras = clientExtraLinks(membership);

  function openConsole() {
    setView("staff");
    router.push(adminHref("/admin", selectedOrganizationSlug));
  }

  return (
    <HubPage title={t("meTitle")}>
      <HubCard>
        <div className="flex items-center gap-4">
          {currentUser?.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
            <img src={currentUser.avatar_url} alt="" className="h-20 w-20 shrink-0 rounded-full object-cover" />
          ) : (
            <span
              aria-hidden="true"
              className="flex h-20 w-20 shrink-0 items-center justify-center rounded-full text-2xl font-extrabold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {initials}
            </span>
          )}
          <div className="min-w-0">
            <p className="truncate text-xl font-extrabold" style={{ color: "var(--text)" }}>{nickname}</p>
            <p className="truncate text-sm" style={{ color: "var(--dim)" }}>{clubs.join(" · ")}</p>
            <Link href="/me/connections" className="mt-1 inline-flex min-h-11 items-center text-sm font-semibold" style={{ color: "var(--text)" }}>
              {tSocial("countsLine", {
                followers: summary.data?.followers_count ?? 0,
                following: summary.data?.following_count ?? 0,
              })}
            </Link>
          </div>
        </div>
      </HubCard>

      <HubList>
        <HubListRow href="/me/referrals" label={t("meReferrals")} detail={t("meReferralsHint")} />
        <HubListRow
          href="/me/buddy"
          label={tBuddy("title")}
          detail={buddyNames || tBuddy("rowHint")}
          badge={<CountBadge count={buddyUnread} label={tBuddy("unreadCount", { count: buddyUnread })} />}
        />
        <HubListRow href="/me/posts" label={t("mePosts")} detail={t("mePostsHint")} />
        <HubListRow href="/me/clubs" label={t("meClubs")} detail={t("meClubsHint")} />
        <HubListRow href="/journal/pantheon" label={t("meSharedPrs")} detail={t("meSharedPrsHint")} />
        <HubListRow href="/me/sharing" label={t("meSharing")} detail={t("meSharingHint")} />
        <HubListRow href="/me/devices" label={tCheckIn("devicesTitle")} detail={tCheckIn("devicesNavHint")} />
        {/* Only for clients of a gym or coach; staff use the console. */}
        {hasBillingProviders ? (
          <HubListRow href="/me/payments" label={t("mePayments")} detail={t("mePaymentsHint")} />
        ) : null}
        <HubListRow href="/me/activity/chats" label={t("meChats")} />
        <HubListRow href="/me/settings" label={t("meSettings")} detail={t("meSettingsHint")} />
        <HubListRow href="/me/settings/interests" label={tFirstRun("interestsTitle")} detail={tFirstRun("interestsHubHint")} />
        <HubListRow href="/me/settings/body" label={tBody("settingsTitle")} detail={tBody("settingsHubHint")} />
        <HubListRow onClick={openProductTour} label={t("meTour")} />
        <HubListRow onClick={openOnboardingChecklist} label={t("meChecklist")} />
        {extras.map((item) => (
          <HubListRow key={item.id} href={adminHref(item.href, selectedOrganizationSlug)} label={tNav(item.labelKey)} />
        ))}
        {hasStaffRole(membership) ? <HubListRow onClick={openConsole} label={t("meConsole")} detail={t("meConsoleHint")} /> : null}
        {/* ADR-170: anyone can open a practice as an independent coach, once. */}
        {ownsCoachPractice(memberships) ? null : (
          <HubListRow href="/me/coach-practice" label={tCoach("me.row")} detail={tCoach("me.rowHint")} />
        )}
        {/* ADR-184: a gym or a coach practice, asked from the Palee team. */}
        {ownsBusiness(memberships) ? null : (
          <HubListRow href="/me/settings#business" label={tBusiness("me.row")} detail={tBusiness("me.rowHint")} />
        )}
      </HubList>

      {memberships.length > 1 ? (
        <HubCard eyebrow={t("meMyBoxes")}>
          <OrganizationSelector variant="menu" />
        </HubCard>
      ) : null}

      <button
        type="button"
        onClick={() => signOut()}
        className="min-h-11 rounded-2xl text-sm font-semibold"
        style={{ color: "var(--danger)", border: "1px solid var(--border)" }}
      >
        {t("signOut")}
      </button>
    </HubPage>
  );
}

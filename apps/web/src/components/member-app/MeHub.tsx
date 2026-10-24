"use client";

import { useTranslations } from "next-intl";

import { ProfileSwitcherMenu } from "@/components/account/ProfileSwitcherMenu";
import { CountBadge } from "@/components/buddy/BuddyBits";
import { activeBuddies, recipientNames, unreadTotal } from "@/components/buddy/buddy-model";
import { useBuddies } from "@/components/buddy/use-buddies";
import { HubCard, HubList, HubListRow, HubPage } from "@/components/member-app/HubParts";
import { MeProfile } from "@/components/member-app/me/MeProfile";
import { usePasswordResets } from "@/components/member-app/me/use-password-resets";
import { useSession } from "@/components/session-provider";
import { CountsLine } from "@/components/social/SocialBits";
import { useSocialSummary } from "@/components/social/use-social";
import { useHasBillingProviders } from "@/lib/billing-providers";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * Εγώ (brief §6.1, §7.11, mockup «me/meLinks»): who I am to others (the
 * profile with «Αναρτήσεις · PRs · Clubs» tabs, `MeProfile`), then the fixed
 * list, in the mockup's order: Φέρε φίλο · Buddy · Τα box και τα clubs μου ·
 * Κοινοποίηση & ορατότητα · Συνδεδεμένες συσκευές · Πληρωμές & αποδείξεις ·
 * Ρυθμίσεις · Βοήθεια & ξενάγηση. Everything else has a home inside one of
 * them (ADR-196): interests, body settings and the business request in
 * Ρυθμίσεις; the box switcher in Τα box και τα clubs μου; the tour, first
 * steps, coach practice and the staff entries in Βοήθεια & ξενάγηση; the
 * chats in the one inbox (Feed ✈). No "More" drawer (brief §4.8).
 */
export function MeHub() {
  const t = useTranslations("MemberApp");
  const tCheckIn = useTranslations("CheckIn");
  const tBuddy = useTranslations("Buddy");
  const summary = useSocialSummary();
  const buddies = useBuddies();
  const buddyNames = recipientNames(activeBuddies(buddies.data), tBuddy("someone"));
  const buddyUnread = unreadTotal(buddies.data);
  const { currentUser, signOut } = useSession();
  const { memberships } = useSelectedMembershipRole();
  const { hasBillingProviders } = useHasBillingProviders();
  const resets = usePasswordResets();
  const nickname = currentUser?.nickname ?? "";
  const initials = nickname.slice(0, 2).toUpperCase() || "?";
  const clubs = memberships.map((entry) => entry.settings?.brand_name?.trim() || entry.organization.name);

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
            <div className="mt-1">
              <CountsLine groups={summary.data?.follow_groups} mine />
            </div>
          </div>
        </div>
      </HubCard>

      <MeProfile postsCount={summary.data?.posts_count ?? 0} />

      {/* ADR-187: the profile switch (also a long press on the avatar tab). */}
      {(currentUser?.profile_count ?? 1) > 1 ? (
        <section className="overflow-hidden rounded-3xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <ProfileSwitcherMenu />
        </section>
      ) : null}

      <HubList>
        <HubListRow href="/me/referrals" label={t("meReferrals")} detail={t("meReferralsHint")} />
        <HubListRow
          href="/me/buddy"
          label={tBuddy("title")}
          detail={buddyNames || tBuddy("rowHint")}
          badge={<CountBadge count={buddyUnread} label={tBuddy("unreadCount", { count: buddyUnread })} />}
        />
        <HubListRow href="/me/clubs" label={t("meClubs")} detail={t("meClubsHint")} />
        <HubListRow href="/me/sharing" label={t("meSharing")} detail={t("meSharingHint")} />
        <HubListRow href="/me/devices" label={tCheckIn("devicesTitle")} detail={tCheckIn("devicesNavHint")} />
        {/* Only for clients of a gym or coach; staff use the console. */}
        {hasBillingProviders ? (
          <HubListRow href="/me/payments" label={t("mePayments")} detail={t("mePaymentsHint")} />
        ) : null}
        <HubListRow href="/me/settings" label={t("meSettings")} detail={t("meSettingsHint")} />
        <HubListRow
          href="/me/help"
          label={t("meHelp")}
          detail={t("meHelpHint")}
          badge={resets.toAct > 0 ? <CountBadge count={resets.toAct} label={t("meHelpResetsWaiting", { count: resets.toAct })} /> : null}
        />
      </HubList>

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

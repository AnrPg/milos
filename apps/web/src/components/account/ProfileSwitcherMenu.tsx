"use client";

import { useTranslations } from "next-intl";

import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useAccountProfiles, useSwitchProfile } from "@/components/account/use-account-profiles";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * ADR-187: the account menu's quick switch to the login's other profiles.
 * Renders nothing unless the login holds more than one profile.
 */
export function ProfileSwitcherMenu() {
  const t = useTranslations("accountProfiles");
  const { currentUser } = useSession();
  const hasOthers = (currentUser?.profile_count ?? 1) > 1;
  const profilesQuery = useAccountProfiles(hasOthers);
  const { switchTo, switchingTo, failed } = useSwitchProfile();

  if (!hasOthers) return null;
  const others = (profilesQuery.data?.profiles ?? []).filter((profile) => !profile.current);
  if (others.length === 0) return null;

  return (
    <div className="border-b py-1" style={{ borderColor: "var(--border)" }}>
      <p className="px-4 pb-1 pt-2 text-[10px] font-bold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
        {t("switchTo")}
      </p>
      {others.map((profile) => (
        <button
          key={profile.id}
          type="button"
          disabled={Boolean(switchingTo)}
          onClick={() => void switchTo(profile.id)}
          className="flex w-full items-center gap-2 px-4 py-2 text-start transition-colors hover:bg-[var(--border)] disabled:opacity-50"
        >
          <PersonAvatar name={profile.display_name} url={profile.avatar_url} size={24} />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              {switchingTo === profile.id ? t("switching") : profile.display_name}
            </span>
            <span className="block truncate text-[11px]" style={{ color: "var(--dim)" }} dir="ltr">
              @{profile.handle}
            </span>
          </span>
        </button>
      ))}
      {failed ? (
        <ErrorNotice variant="field" className="mx-4 my-1">{t("switchError")}</ErrorNotice>
      ) : null}
    </div>
  );
}

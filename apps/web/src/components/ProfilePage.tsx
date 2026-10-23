"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useLocale, useTranslations } from "next-intl";

import { SESSION_UPDATED_EVENT } from "@/api/client";
import { signOutAllDevices } from "@/api/auth";
import { getAvatarUploadUrl, updateAvatar, updateProfile } from "@/api/profile";
import { IdentitySettings, IDENTITY_FORM_ID } from "@/components/account/IdentitySettings";
import { ProfilesSection } from "@/components/account/ProfilesSection";
import { RecoveryCodesSection } from "@/components/account/RecoveryCodesSection";
import { BusinessAccountSettings } from "@/components/business/BusinessAccountSettings";
import { AvatarEditorModal } from "@/components/profile/AvatarEditorModal";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { AroundAreaSetting } from "@/components/around/AroundSettings";
import { JournalSettingsSections } from "@/components/providers/JournalSettings";
import { isSupportedAvatarSource } from "@/components/profile/avatar-crop";
import { useSession } from "@/components/session-provider";
import { usePushNotifications } from "@/hooks/usePushNotifications";
import {
  isAppLocale,
  LOCALE_NAMES,
  persistLocaleCookie,
  SUPPORTED_LOCALES,
  type AppLocale,
} from "@/i18n/locales";
import { PageHeader } from "@/components/PageHeader";
import { ReplayTourButton } from "@/components/onboarding/Onboarding";
import { OutboxSettingsCard } from "@/components/outbox/OutboxSettingsCard";
import { ThemeSetting } from "@/components/profile/ThemeSetting";
import { Select } from "@/components/ui/Select";

function FieldGroup({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
        {label}
      </label>
      {children}
    </div>
  );
}

type CurrentUserWithAvatar = {
  id: string;
  nickname: string;
  role: string;
  avatar_url?: string | null;
  preferred_locale: string;
  vendor?: boolean | null;
};

export function ProfilePage() {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const tProfile = useTranslations("Profile");
  const tAround = useTranslations("Around");
  const tMe = useTranslations("MemberApp");
  const tAccount = useTranslations("accountProfiles");
  const { tokens, currentUser, signOut } = useSession();
  const user = currentUser as CurrentUserWithAvatar | null;
  useLegacySectionRedirects();
  const push = usePushNotifications(tokens?.access_token);

  const [languagePending, setLanguagePending] = useState(false);
  const [languageError, setLanguageError] = useState<string | null>(null);
  const [securityPending, setSecurityPending] = useState(false);
  const [securityError, setSecurityError] = useState<string | null>(null);

  const [avatarPending, setAvatarPending] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(user?.avatar_url ?? null);
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);


  function broadcastUserUpdate(updatedUser: Partial<CurrentUserWithAvatar> & { id: string }) {
    if (!tokens) return;
    window.dispatchEvent(
      new CustomEvent(SESSION_UPDATED_EVENT, {
        detail: {
          tokens,
          currentUser: { ...currentUser, ...updatedUser },
        },
      }),
    );
  }

  async function handleSignOutAllDevices() {
    if (!tokens) return;
    setSecurityError(null);
    setSecurityPending(true);

    try {
      await signOutAllDevices(tokens.access_token);
      signOut();
    } catch (error) {
      setSecurityError(error instanceof Error ? localizeError(error, i18n) : i18n("couldNotRevokeSessions41a1176"));
      setSecurityPending(false);
    }
  }

  async function handleAvatarFile(file: File) {
    if (!tokens) return;
    setAvatarError(null);
    setAvatarPending(true);

    try {
      const { upload_url, key, required_headers } =
        await getAvatarUploadUrl(tokens.access_token, file);

      const uploadRes = await fetch(upload_url, {
        method: "PUT",
        body: file,
        headers: required_headers,
      });

      if (!uploadRes.ok) throw new Error(i18n("uploadToStorageFailed1daa4c3"));

      const result = await updateAvatar(tokens.access_token, key);
      broadcastUserUpdate(result.user);
      setAvatarPreview(result.user.avatar_url);
      setAvatarFile(null);
    } catch (err) {
      setAvatarError(err instanceof Error ? localizeError(err, i18n) : i18n("avatarUploadFailed8d620ac"));
    } finally {
      setAvatarPending(false);
    }
  }

  function selectAvatarFile(file: File) {
    setAvatarError(null);
    if (!isSupportedAvatarSource(file)) {
      setAvatarError(tProfile("avatarUnsupportedType"));
      return;
    }
    setAvatarFile(file);
  }

  async function handleLanguageChange(nextLocale: AppLocale) {
    if (!tokens || nextLocale === user?.preferred_locale) return;

    setLanguageError(null);
    setLanguagePending(true);

    try {
      const result = await updateProfile(tokens.access_token, { preferred_locale: nextLocale });
      broadcastUserUpdate(result.user);
      persistLocaleCookie(nextLocale);
      window.location.reload();
    } catch {
      setLanguageError(tProfile("languageError"));
      setLanguagePending(false);
    }
  }

  return (
    <main className="min-h-screen px-6 py-10 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-3xl space-y-4">
        <PageHeader title={tProfile("title")} actions={<ReplayTourButton />} />

        <Link
          href="/me/sharing"
          className="flex items-center justify-between gap-4 rounded-[2.4rem] p-8"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <span>
            <span className="block text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>{tMe("meSharing")}</span>
            <span className="mt-1 block text-sm" style={{ color: "var(--muted)" }}>{tMe("meSharingHint")}</span>
          </span>
          <span aria-hidden="true" className="text-xl" style={{ color: "var(--dim)" }}>›</span>
        </Link>

        <div className="flex justify-end">
          <button
            type="submit"
            form={IDENTITY_FORM_ID}
            className="rounded-xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {i18n("saveChanges179359b")}
          </button>
        </div>

        <ProfilesSection />


        <CollapsibleSection
          id="language-region"
          title={tProfile("languageTitle")}
          description={tProfile("languageDescription")}
          defaultOpen
        >
          <FieldGroup label={tProfile("languageLabel")}>
            <Select
              aria-label={tProfile("languageLabel")}
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              disabled={languagePending}
              value={isAppLocale(user?.preferred_locale) ? user.preferred_locale : locale}
              onValueChange={(value) => void handleLanguageChange(value as AppLocale)}
              style={{
                background: "var(--panel-muted)",
                border: "1px solid var(--border)",
                color: "var(--text)",
              }}
            >
              {SUPPORTED_LOCALES.map((supportedLocale) => (
                <option key={supportedLocale} value={supportedLocale}>
                  {LOCALE_NAMES[supportedLocale]}
                </option>
              ))}
            </Select>
          </FieldGroup>
          {languagePending ? (
            <p className="mt-3 text-sm" style={{ color: "var(--muted)" }}>
              {tProfile("languageSaved")}
            </p>
          ) : null}
          {languageError ? (
            <p className="mt-3 text-sm font-semibold" style={{ color: "var(--danger)" }}>
              {languageError}
            </p>
          ) : null}
        </CollapsibleSection>

        <CollapsibleSection id="theme" title={tProfile("themeTitle")} description={tProfile("themeDescription")}>
          <ThemeSetting />
        </CollapsibleSection>

        <CollapsibleSection id="around-area" title={tAround("areaTitle")} description={tAround("areaSettingHint")} defaultOpen>
          <AroundAreaSetting />
        </CollapsibleSection>

        <JournalSettingsSections />

        <OutboxSettingsCard />

        <CollapsibleSection
          id="security"
          title={i18n("securityf25ce1b")}
          description={i18n("activeSessionsAndAccountProtection4aeac5f")}
        >
          <div className="space-y-4">
            {push.supported && push.enabled && (
              <div className="rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                <div className="flex items-center justify-between gap-4">
                  <div>
                    <p className="text-sm font-semibold" style={{ color: "var(--success)" }}>
                      {i18n("browserPushIsOnForThisDevicea620272")}
                    </p>
                    <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
                      {i18n("thisChoiceAppliesOnlyToThisBrowserAnd0ca4181")}
                    </p>
                  </div>
                  {push.enabled ? (
                    <button
                      type="button"
                      disabled={push.busy}
                      onClick={() => void push.disablePush()}
                      className="shrink-0 rounded-xl px-4 py-2 text-sm font-semibold disabled:opacity-50"
                      style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
                    >
                      {push.busy ? i18n("disabling3bf14ec") : i18n("disable9a7d4e0")}
                    </button>
                  ) : null}
                </div>
                {push.error ? <p className="mt-3 text-xs font-semibold" style={{ color: "var(--danger)" }}>{push.error}</p> : null}
              </div>
            )}
            <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
              {i18n("revokeEveryRefreshSessionIncludingThisBrowserYoudd5d38f")}
            </p>
            <button
              type="button"
              disabled={securityPending}
              onClick={() => void handleSignOutAllDevices()}
              className="rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
            >
              {securityPending ? i18n("revokingSessions8eee998") : i18n("signOutAllDevicesf14a071")}
            </button>
            {securityError ? <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{securityError}</p> : null}
          </div>
        </CollapsibleSection>

        <RecoveryCodesSection />

        <BusinessAccountSettings />

        <CollapsibleSection
          id="personal"
          title={i18n("personalInfo87a403c")}
          description={tAccount("identityDescription")}
          defaultOpen
        >
          <IdentitySettings />
        </CollapsibleSection>

        <CollapsibleSection id="avatar" title={i18n("avatar7631b26")} description={i18n("profilePictureaeb8371")}>
          <div className="space-y-5">
            {avatarPreview && (
              <div className="flex items-center gap-4">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={avatarPreview}
                  alt={i18n("avatarPreview9d0ac09")}
                  className="h-20 w-20 rounded-full object-cover"
                  style={{ border: "2px solid var(--border)" }}
                />
                <p className="text-sm" style={{ color: "var(--muted)" }}>
                  {i18n("currentAvatar8634e3c")}
                </p>
              </div>
            )}

            <input
              ref={fileInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/gif,image/bmp,image/avif,.jpg,.jpeg,.png,.webp,.gif,.bmp,.avif"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) selectAvatarFile(file);
                e.target.value = "";
              }}
            />

            <p className="text-xs leading-5" style={{ color: "var(--muted)" }}>
              {tProfile("avatarFormatHelp")}
            </p>

            <button
              type="button"
              disabled={avatarPending}
              onClick={() => fileInputRef.current?.click()}
              className="rounded-xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
              style={{
                background: "var(--panel-muted)",
                border: "1px solid var(--border)",
                color: "var(--text)",
              }}
            >
              {avatarPending ? i18n("uploadingd921a79") : avatarPreview ? i18n("changeAvatar60f2e98") : i18n("uploadAvatareb634e9")}
            </button>

            {avatarError && (
              <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>
                {avatarError}
              </p>
            )}
          </div>
        </CollapsibleSection>

        {avatarFile ? (
          <AvatarEditorModal
            file={avatarFile}
            pending={avatarPending}
            uploadError={avatarError}
            onCancel={() => setAvatarFile(null)}
            onSave={handleAvatarFile}
          />
        ) : null}

      </div>
    </main>
  );
}

/**
 * Sections that left Ρυθμίσεις in ADR-137 keep working from old links:
 * the Vault and training history live in Ημερολόγιο › Vault, PR sharing and
 * rest days in Εγώ › Κοινοποίηση & ορατότητα.
 */
function useLegacySectionRedirects() {
  const router = useRouter();
  useEffect(() => {
    const target = LEGACY_SECTION_TARGETS[window.location.hash];
    if (target) router.replace(target);
  }, [router]);
}

const LEGACY_SECTION_TARGETS: Record<string, string> = {
  "#vault": "/journal/vault",
  "#history": "/journal/vault#history",
  "#pr-sharing": "/me/sharing#pr-sharing",
  "#training-schedule": "/me/sharing#training-schedule",
  "#account-activity": "/journal/reviews",
};

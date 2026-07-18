"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { SESSION_UPDATED_EVENT } from "@/api/client";
import { signOutAllDevices } from "@/api/auth";
import { fetchMyReviews } from "@/api/reviews";
import { getAvatarUploadUrl, updateAvatar, updateProfile } from "@/api/profile";
import { fetchGamificationPreferences, updateGamificationPreferences } from "@/api/gamification";
import { ReviewList } from "@/components/my-reviews";
import { AvatarEditorModal } from "@/components/profile/AvatarEditorModal";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";
import { usePushNotifications } from "@/hooks/usePushNotifications";
import {
  isAppLocale,
  LOCALE_NAMES,
  persistLocaleCookie,
  SUPPORTED_LOCALES,
  type AppLocale,
} from "@/i18n/locales";

function CollapsibleSection({
  id,
  title,
  description,
  defaultOpen = false,
  children,
}: {
  id: string;
  title: string;
  description?: string;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <section
      id={id}
      className="overflow-hidden rounded-[2.4rem]"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <button
        className="flex w-full items-center justify-between gap-4 p-8 text-start"
        type="button"
        onClick={() => setOpen((v) => !v)}
      >
        <div>
          <p
            className="text-sm font-semibold uppercase tracking-[0.24em]"
            style={{ color: "var(--primary)" }}
          >
            {title}
          </p>
          {description && (
            <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
              {description}
            </p>
          )}
        </div>
        <span className="text-xl font-light" style={{ color: "var(--dim)" }}>
          {open ? "−" : "+"}
        </span>
      </button>
      {open && (
        <div className="border-t px-8 pb-8 pt-6" style={{ borderColor: "var(--border)" }}>
          {children}
        </div>
      )}
    </section>
  );
}

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

function TextInput(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
      style={{
        background: "var(--panel-muted)",
        border: "1px solid var(--border)",
        color: "var(--text)",
      }}
    />
  );
}

type CurrentUserWithAvatar = {
  id: string;
  nickname: string;
  role: string;
  avatar_url?: string | null;
  preferred_locale: string;
};

export function ProfilePage() {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const dayLabels = Array.from({ length: 7 }, (_, dayOffset) =>
    new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" }).format(
      new Date(Date.UTC(2024, 0, 7 + dayOffset)),
    ),
  );
  const tProfile = useTranslations("Profile");
  const { tokens, currentUser, signOut } = useSession();
  const user = currentUser as CurrentUserWithAvatar | null;
  const push = usePushNotifications(tokens?.access_token);

  const [nicknameValue, setNicknameValue] = useState(user?.nickname ?? "");
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [personalError, setPersonalError] = useState<string | null>(null);
  const [personalSuccess, setPersonalSuccess] = useState<string | null>(null);
  const [personalPending, setPersonalPending] = useState(false);
  const [languagePending, setLanguagePending] = useState(false);
  const [languageError, setLanguageError] = useState<string | null>(null);
  const [securityPending, setSecurityPending] = useState(false);
  const [securityError, setSecurityError] = useState<string | null>(null);

  const [avatarPending, setAvatarPending] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(user?.avatar_url ?? null);
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const queryClient = useQueryClient();

  const reviewsQuery = useQuery({
    queryKey: ["my", "reviews"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchMyReviews(tokens!.access_token),
  });

  const prefsQuery = useQuery({
    queryKey: ["gamification", "preferences"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchGamificationPreferences(tokens!.access_token),
  });

  const [offDaysDraft, setOffDaysDraft] = useState<number[] | null>(null);
  const offDays = offDaysDraft ?? prefsQuery.data?.off_days ?? [];

  const updatePrefsMutation = useMutation({
    mutationFn: async (days: number[]) => {
      if (!tokens) throw new Error(i18n("notAuthenticated0c91acb"));
      return updateGamificationPreferences(tokens.access_token, { off_days: days });
    },
    onSuccess: (data) => {
      void queryClient.invalidateQueries({ queryKey: ["gamification", "preferences"] });
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
      setOffDaysDraft(data.off_days);
    },
  });

  function toggleOffDay(dow: number) {
    const current = offDays;
    const next = current.includes(dow)
      ? current.filter((d) => d !== dow)
      : current.length >= 3
        ? current
        : [...current, dow];
    setOffDaysDraft(next);
    updatePrefsMutation.mutate(next);
  }

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

  async function handlePersonalSave(e: React.FormEvent) {
    e.preventDefault();
    if (!tokens) return;

    setPersonalError(null);
    setPersonalSuccess(null);
    setPersonalPending(true);

    try {
      const payload: Record<string, string> = {};
      if (nicknameValue.trim() && nicknameValue.trim() !== user?.nickname) {
        payload.nickname = nicknameValue.trim();
      }
      if (newPassword) {
        payload.current_password = currentPassword;
        payload.password = newPassword;
      }

      if (Object.keys(payload).length === 0) {
        setPersonalSuccess(i18n("nothingToUpdate928017b"));
        return;
      }

      const result = await updateProfile(tokens.access_token, payload);
      broadcastUserUpdate(result.user);
      setNicknameValue(result.user.nickname);
      setCurrentPassword("");
      setNewPassword("");
      if (payload.password) {
        signOut();
      } else {
        setPersonalSuccess(i18n("profileUpdatedbcf7629"));
      }
    } catch (err) {
      setPersonalError(err instanceof Error ? localizeError(err, i18n) : i18n("updateFailed19a9955"));
    } finally {
      setPersonalPending(false);
    }
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
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
      setAvatarError(tProfile("avatarUnsupportedType"));
      return;
    }
    if (file.size > 5 * 1_024 * 1_024) {
      setAvatarError(tProfile("avatarTooLarge"));
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
        <TransientHero label={i18n("profileIntroductioncf30917")}>
        <div className="mb-4">
          <p className="text-xs font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
            {tProfile("eyebrow")}
          </p>
          <h1 className="mt-1 text-3xl font-black" style={{ color: "var(--text)" }}>
            {tProfile("title")}
          </h1>
        </div>
        </TransientHero>

        <div className="flex justify-end">
          <button
            type="submit"
            form="profile-personal-form"
            disabled={personalPending}
            className="rounded-xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {personalPending ? i18n("saving56a2285") : i18n("saveChanges179359b")}
          </button>
        </div>

        <CollapsibleSection
          id="language-region"
          title={tProfile("languageTitle")}
          description={tProfile("languageDescription")}
          defaultOpen
        >
          <FieldGroup label={tProfile("languageLabel")}>
            <select
              aria-label={tProfile("languageLabel")}
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              disabled={languagePending}
              value={isAppLocale(user?.preferred_locale) ? user.preferred_locale : locale}
              onChange={(event) => void handleLanguageChange(event.target.value as AppLocale)}
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
            </select>
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
              style={{ background: "var(--danger)", color: "white" }}
            >
              {securityPending ? i18n("revokingSessions8eee998") : i18n("signOutAllDevicesf14a071")}
            </button>
            {securityError ? <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{securityError}</p> : null}
          </div>
        </CollapsibleSection>

        <CollapsibleSection
          id="personal"
          title={i18n("personalInfo87a403c")}
          description={i18n("nicknameAndPassword3e84316")}
          defaultOpen
        >
          <form id="profile-personal-form" className="space-y-5" onSubmit={(e) => void handlePersonalSave(e)}>
            <FieldGroup label={i18n("nicknamece2bd99")}>
              <TextInput
                value={nicknameValue}
                onChange={(e) => setNicknameValue(e.target.value)}
                placeholder={i18n("yourNicknameb5c8b4b")}
                minLength={3}
                maxLength={30}
              />
            </FieldGroup>

            <div className="border-t pt-5" style={{ borderColor: "var(--border)" }}>
              <p className="text-xs font-semibold uppercase tracking-[0.18em] mb-4" style={{ color: "var(--muted)" }}>
                {i18n("changePasswordLeaveBlankToKeepCurrent6e6fc07")}
              </p>
              <div className="space-y-3">
                <FieldGroup label={i18n("currentPassword19dff4d")}>
                  <TextInput
                    type="password"
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    placeholder={i18n("enterCurrentPassword149b393")}
                    autoComplete="current-password"
                  />
                </FieldGroup>
                <FieldGroup label={i18n("newPasswordd850ee1")}>
                  <TextInput
                    type="password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder={i18n("passwordRules0c63f14")}
                    minLength={4}
                    autoComplete="new-password"
                  />
                </FieldGroup>
              </div>
            </div>

            {personalError && (
              <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>
                {personalError}
              </p>
            )}
            {personalSuccess && (
              <p className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
                {personalSuccess}
              </p>
            )}

            <button
              type="submit"
              disabled={personalPending}
              className="rounded-xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {personalPending ? i18n("saving56a2285") : i18n("saveChanges179359b")}
            </button>
          </form>
        </CollapsibleSection>

        <CollapsibleSection
          id="training-schedule"
          title={i18n("trainingSchedule80e51e2")}
          description={i18n("markYourWeeklyRestDaysUpTo5ee5b72a")}
        >
          <div className="space-y-5">
            <p className="text-sm" style={{ color: "var(--muted)" }}>
              {i18n("offDaysAreTransparentToYourStreakMissingb808660")}
            </p>
            <div className="flex flex-wrap gap-2">
              {dayLabels.map((label, dow) => {
                const selected = offDays.includes(dow);
                const disabled = !selected && offDays.length >= 5;
                return (
                  <button
                    key={dow}
                    type="button"
                    disabled={disabled || updatePrefsMutation.isPending}
                    onClick={() => toggleOffDay(dow)}
                    className="rounded-xl px-4 py-2 text-sm font-semibold transition-opacity disabled:opacity-40"
                    style={{
                      background: selected ? "var(--primary)" : "var(--panel-muted)",
                      color: selected ? "var(--primary-contrast)" : "var(--text-soft)",
                      border: selected
                        ? "1px solid var(--primary)"
                        : "1px solid var(--border)",
                    }}
                  >
                    {label}
                  </button>
                );
              })}
            </div>
            {updatePrefsMutation.isError && (
              <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>
                {i18n("failedToSavePleaseTryAgainb68b7e7")}
              </p>
            )}
          </div>
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
              accept="image/jpeg,image/png,image/webp"
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

        <CollapsibleSection
          id="account-activity"
          title={i18n("accountActivity2263296")}
          description={i18n("yourReviewsAndHistory4a3fb33")}
        >
          <div className="space-y-4">
            <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--muted)" }}>
              {i18n("myReviewsHistorycdeb034")}
            </p>
            {reviewsQuery.isLoading ? (
              <p className="text-sm" style={{ color: "var(--dim)" }}>
                {i18n("loadingReviews1c4171c")}
              </p>
            ) : (
              <ReviewList reviews={(reviewsQuery.data?.reviews ?? []) as Parameters<typeof ReviewList>[0]["reviews"]} />
            )}
          </div>
        </CollapsibleSection>
      </div>
    </main>
  );
}

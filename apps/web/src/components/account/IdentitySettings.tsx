"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { SESSION_UPDATED_EVENT } from "@/api/client";
import { updateProfile, type ProfileUpdate } from "@/api/profile";
import { cleanHandleInput, describeAccountError } from "@/components/account/account-model";
import { HandleField } from "@/components/account/HandleField";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

export const IDENTITY_FORM_ID = "profile-personal-form";

const inputStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

function Field({ id, label, hint, children }: { id: string; label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <label
        htmlFor={id}
        className="block text-xs font-semibold uppercase tracking-[0.18em]"
        style={{ color: "var(--muted)" }}
      >
        {label}
      </label>
      {children}
      {hint ? <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{hint}</p> : null}
    </div>
  );
}

/**
 * Ρυθμίσεις › Personal info (ADR-187): this profile's display name and
 * @handle, and the login's email and password (shared by every profile of
 * it, so changing either asks for the current password).
 */
export function IdentitySettings() {
  const t = useTranslations("accountProfiles");
  const i18n = useUiTranslations();
  const { tokens, currentUser, signOut } = useSession();
  const [displayName, setDisplayName] = useState(currentUser?.display_name ?? currentUser?.nickname ?? "");
  const [handle, setHandle] = useState(currentUser?.handle ?? "");
  const [email, setEmail] = useState(currentUser?.email ?? "");
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const emailChanged = email.trim() !== "" && email.trim().toLowerCase() !== (currentUser?.email ?? "").toLowerCase();
  const needsPassword = emailChanged || newPassword !== "";

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!tokens || !currentUser || pending) return;
    setError(null);
    setSuccess(null);

    const payload: ProfileUpdate = {};
    const nextName = displayName.trim();
    const nextHandle = cleanHandleInput(handle);
    if (nextName && nextName !== (currentUser.display_name ?? currentUser.nickname)) payload.display_name = nextName;
    if (nextHandle && nextHandle !== currentUser.handle) payload.handle = nextHandle;
    if (emailChanged) payload.email = email.trim();
    if (newPassword) payload.password = newPassword;
    if (needsPassword) {
      if (!currentPassword) {
        setError(t("currentPasswordNeeded"));
        return;
      }
      payload.current_password = currentPassword;
    }

    if (Object.keys(payload).length === 0) {
      setSuccess(i18n("nothingToUpdate928017b"));
      return;
    }

    setPending(true);
    try {
      const result = await updateProfile(tokens.access_token, payload);
      window.dispatchEvent(
        new CustomEvent(SESSION_UPDATED_EVENT, {
          detail: { tokens, currentUser: { ...currentUser, ...result.user } },
        }),
      );
      setDisplayName(result.user.display_name ?? result.user.nickname ?? nextName);
      setHandle(result.user.handle ?? nextHandle);
      setEmail(result.user.email ?? email);
      setCurrentPassword("");
      setNewPassword("");
      if (payload.password) {
        signOut();
        return;
      }
      setSuccess(i18n("profileUpdatedbcf7629"));
    } catch (err) {
      const described = describeAccountError(err);
      setError(described ? t(described.key, described.values) : localizeError(err, i18n));
    } finally {
      setPending(false);
    }
  }

  return (
    <form id={IDENTITY_FORM_ID} className="space-y-5" onSubmit={(event) => void submit(event)}>
      <Field id="identity-display-name" label={t("displayNameLabel")} hint={t("displayNameHint")}>
        <input
          id="identity-display-name"
          value={displayName}
          onChange={(event) => setDisplayName(event.target.value)}
          maxLength={50}
          autoComplete="nickname"
          className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
          style={inputStyle}
        />
      </Field>

      <HandleField
        value={handle}
        onChange={setHandle}
        unchangedHandle={currentUser?.handle}
        disabled={pending}
        hint={t("handleChangeRules")}
      />

      <div className="space-y-4 border-t pt-5" style={{ borderColor: "var(--border)" }}>
        <p className="text-xs leading-5" style={{ color: "var(--muted)" }}>{t("loginSharedNote")}</p>
        <Field id="identity-email" label={t("emailLabel")}>
          <input
            id="identity-email"
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            autoComplete="email"
            className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
            style={inputStyle}
            dir="ltr"
          />
        </Field>
        <Field id="identity-new-password" label={t("newPasswordLabel")} hint={t("newPasswordHint")}>
          <input
            id="identity-new-password"
            type="password"
            value={newPassword}
            onChange={(event) => setNewPassword(event.target.value)}
            minLength={4}
            autoComplete="new-password"
            className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
            style={inputStyle}
          />
        </Field>
        {needsPassword ? (
          <Field id="identity-current-password" label={t("currentPasswordLabel")} hint={t("currentPasswordHint")}>
            <input
              id="identity-current-password"
              type="password"
              value={currentPassword}
              onChange={(event) => setCurrentPassword(event.target.value)}
              autoComplete="current-password"
              required
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              style={inputStyle}
            />
          </Field>
        ) : null}
      </div>

      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      {success ? <p className="text-sm font-semibold" style={{ color: "var(--primary)" }}>{success}</p> : null}

      <button
        type="submit"
        disabled={pending}
        className="rounded-xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {pending ? i18n("saving56a2285") : i18n("saveChanges179359b")}
      </button>
    </form>
  );
}

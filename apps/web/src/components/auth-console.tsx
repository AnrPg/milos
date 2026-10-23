"use client";





import { PaleeMark } from "@/components/branding/PaleeMark";
import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useRouter, useSearchParams } from "next/navigation";

import {
  inspectInvitation,
  type InvitationInspection,
} from "@/api/auth";
import { AuthField } from "@/components/auth/AuthField";
import { AuthNotice } from "@/components/auth/AuthShell";
import { BusinessSignUpLink } from "@/components/business/BusinessSignUp";
import { RecoveryCodesOffer } from "@/components/auth/RecoveryCodesOffer";
import { SignupHandleField, useHandleSuggestion } from "@/components/auth/SignupHandleField";
import {
  passwordLongEnough,
  registerFailure,
  type FieldErrors,
} from "@/components/auth/auth-errors";
import { getAvatarUploadUrl, updateAvatar } from "@/api/profile";
import { useSession } from "@/components/session-provider";
import { markReferralNewAccount } from "@/lib/referral-claim";

type Mode = "register" | "login";

type RegisterForm = {
  display_name: string;
  handle: string;
  email: string;
  password: string;
  role: "member" | "athlete";
};
type LoginForm = { identifier: string; password: string };

const initialRegister: RegisterForm = { display_name: "", handle: "", password: "", role: "member", email: "" };
const initialLogin: LoginForm = { identifier: "", password: "" };

const MAX_DISPLAY_NAME_LENGTH = 50;

// ADR-187: the server folds and fully checks the handle; this only catches
// what is plainly missing before a round trip.
function invalidRegisterFields(form: RegisterForm, t: (key: string) => string): FieldErrors {
  const errors: FieldErrors = {};
  const displayName = form.display_name.trim();

  if (displayName.length === 0 || displayName.length > MAX_DISPLAY_NAME_LENGTH) {
    errors.display_name = [t("displayNameRule")];
  }
  if (form.handle.trim().length < 3) errors.handle = [t("handleRule")];
  if (!passwordLongEnough(form.password)) errors.password = [t("passwordRule")];

  return errors;
}

function invalidLoginFields(form: LoginForm, t: (key: string) => string): FieldErrors {
  const errors: FieldErrors = {};

  if (form.identifier.trim().length === 0) errors.identifier = [t("identifierRequired")];
  if (form.password.length === 0) errors.password = [t("passwordRequired")];

  return errors;
}

export function AuthConsole({ initialMode = "login" }: { initialMode?: Mode }) {
  const i18n = useUiTranslations();
  const t = useTranslations("authRecovery");
  const router = useRouter();
  const searchParams = useSearchParams();
  const { signIn, signUp, signUpInvited, status, tokens } = useSession();

  const [mode, setMode] = useState<Mode>(() =>
    searchParams.get("token") ? "register" : initialMode,
  );
  const [registerForm, setRegisterForm] = useState<RegisterForm>(() => {
    // A public join link (/join/<slug>) passes the role the organization grants.
    const requestedRole = searchParams.get("role");
    return requestedRole === "athlete" || requestedRole === "member"
      ? { ...initialRegister, role: requestedRole }
      : initialRegister;
  });
  const [loginForm, setLoginForm] = useState<LoginForm>(initialLogin);
  // The handle follows the display name until the person types their own.
  const [handleEdited, setHandleEdited] = useState(false);
  // After sign-up, recovery codes are offered once before moving on.
  const [offerRecoveryCodes, setOfferRecoveryCodes] = useState(false);
  const registeringRef = useRef(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const [invitationToken, setInvitationToken] = useState(
    () => searchParams.get("token") ?? "",
  );
  const [invitation, setInvitation] = useState<InvitationInspection | null>(null);

  useEffect(() => {
    const token = invitationToken.trim();
    if (token.length < 20) return;

    let cancelled = false;
    const timer = setTimeout(() => {
      void inspectInvitation(token)
        .then((result) => {
          if (!cancelled) {
            setInvitation(result);
            setError(null);
          }
        })
        .catch((caught) => {
          if (!cancelled) {
            setInvitation(null);
            setError(localizeError(caught, i18n));
          }
        });
    }, 300);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [invitationToken, i18n]);

  // Stored in a ref so the post-registration upload effect doesn't need it as a dep
  const pendingAvatarRef = useRef<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const continueAfterAuth = useCallback(() => {
    router.replace(searchParams.get("next") || "/");
  }, [router, searchParams]);

  useEffect(() => {
    if (status !== "authenticated" || registeringRef.current) return;
    continueAfterAuth();
  }, [continueAfterAuth, status]);

  const applySuggestedHandle = useCallback(
    (handle: string) => setRegisterForm((form) => ({ ...form, handle })),
    [],
  );
  useHandleSuggestion(registerForm.display_name, mode === "register" && !handleEdited, applySuggestedHandle);

  // After registration the session is committed and tokens become available —
  // upload the chosen avatar file at that point
  useEffect(() => {
    if (status !== "authenticated" || !pendingAvatarRef.current || !tokens) return;
    const file = pendingAvatarRef.current;
    const token = tokens.access_token;
    pendingAvatarRef.current = null;

    void (async () => {
      try {
        const { upload_url, key, required_headers } = await getAvatarUploadUrl(token, file);
        await fetch(upload_url, { method: "PUT", body: file, headers: required_headers });
        await updateAvatar(token, key);
      } catch {
        // non-blocking: user is signed in even if avatar upload fails
      }
    })();
  }, [status, tokens]);

  function handleAvatarChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    if (avatarPreview) URL.revokeObjectURL(avatarPreview);
    pendingAvatarRef.current = file;
    setAvatarPreview(file ? URL.createObjectURL(file) : null);
  }

  async function runAction(action: string, effect: () => Promise<void>) {
    setBusyAction(action);
    setError(null);
    setFieldErrors({});
    try {
      await effect();
    } catch (err) {
      const failure = registerFailure(
        err,
        t,
        (caught) =>
          caught instanceof Error ? localizeError(caught, i18n) : i18n("unexpectedRequestFailurea7ffd06"),
        i18n("apiValidationField"),
      );
      setError(failure.message);
      setFieldErrors(failure.fieldErrors);
    } finally {
      setBusyAction(null);
    }
  }

  const passwordResetDone = searchParams.get("reset") === "done";

  function validate(errors: FieldErrors) {
    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  }

  function switchMode(next: Mode) {
    setMode(next);
    setError(null);
    setFieldErrors({});
  }

  return (
    <main
      className="flex min-h-screen items-center justify-center px-6 py-10"
      style={{ background: "var(--bg)" }}
    >
      <div className="w-full max-w-md">
        <div
          className="rounded-[2rem] p-7"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          {offerRecoveryCodes ? <RecoveryCodesOffer onSkip={continueAfterAuth} /> : <>
          {/* Mode toggle */}
          <div className="mb-7 flex justify-center">
            <div
              className="inline-flex rounded-full p-1 text-sm"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)" }}
            >
              <button
                className="rounded-full px-5 py-2 transition-colors"
                style={
                  mode === "register"
                    ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                    : { background: "transparent", color: "var(--dim)" }
                }
                onClick={() => switchMode("register")}
                type="button"
              >
                {i18n("registerd672995")}
              </button>
              <button
                className="rounded-full px-5 py-2 transition-colors"
                style={
                  mode === "login"
                    ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                    : { background: "transparent", color: "var(--dim)" }
                }
                onClick={() => switchMode("login")}
                type="button"
              >
                {i18n("login4e5a289")}
              </button>
            </div>
          </div>

          <div className="mb-6 text-center">
            <PaleeMark className="mx-auto mb-3 h-12 w-12" />
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
              {i18n("brandName")}
            </p>
            <h1 className="mt-2 text-2xl font-bold tracking-tight" style={{ color: "var(--text)" }}>
              {mode === "register" ? i18n("createYourAccount4046b58") : i18n("signInada2e9e")}
            </h1>
          </div>

          <div className="space-y-4">
            {mode === "register" ? (
              <>
                {/* Avatar picker */}
                <div className="flex flex-col items-center gap-3 pb-2">
                  <button
                    type="button"
                    className="relative flex h-20 w-20 items-center justify-center overflow-hidden rounded-full transition-opacity hover:opacity-80"
                    style={{ background: "var(--border)", border: "2px dashed var(--border-strong)" }}
                    onClick={() => fileInputRef.current?.click()}
                  >
                    {avatarPreview ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={avatarPreview} alt={i18n("avatarPreview9d0ac09")} className="h-full w-full object-cover" />
                    ) : (
                      <span className="text-2xl" style={{ color: "var(--dim)" }}>+</span>
                    )}
                  </button>
                  <button
                    type="button"
                    className="text-xs font-semibold"
                    style={{ color: "var(--primary)" }}
                    onClick={() => fileInputRef.current?.click()}
                  >
                    {avatarPreview ? i18n("changePhotoed5690c") : i18n("uploadPhoto69abef7")}
                  </button>
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={handleAvatarChange}
                  />
                </div>

                <AuthField
                  label={t("displayNameLabel")}
                  value={registerForm.display_name}
                  autoComplete="name"
                  placeholder={t("displayNamePlaceholder")}
                  maxLength={MAX_DISPLAY_NAME_LENGTH}
                  errors={fieldErrors.display_name}
                  onChange={(display_name) => setRegisterForm((f) => ({ ...f, display_name }))}
                />

                <SignupHandleField
                  value={registerForm.handle}
                  errors={fieldErrors.handle}
                  onChange={(handle) => {
                    // Clearing the handle hands it back to the display name.
                    setHandleEdited(handle.length > 0);
                    setRegisterForm((f) => ({ ...f, handle }));
                  }}
                />

                <AuthField
                  label={i18n("emailAddress")}
                  value={registerForm.email}
                  type="email"
                  inputMode="email"
                  autoComplete="email"
                  placeholder={i18n("emailAddressPlaceholder")}
                  hint={t("emailNotice")}
                  errors={fieldErrors.email}
                  onChange={(email) => setRegisterForm((f) => ({ ...f, email }))}
                />

                <AuthField
                  label={i18n("password8be3c94")}
                  value={registerForm.password}
                  type="password"
                  autoComplete="new-password"
                  placeholder={t("passwordRule")}
                  errors={fieldErrors.password}
                  onChange={(password) => setRegisterForm((f) => ({ ...f, password }))}
                />

                <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                  {i18n("adminRegistrationCode")}
                  <input
                    autoComplete="off"
                    className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
                    style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
                    value={invitationToken}
                    onChange={(event) => {
                      setInvitation(null);
                      setError(null);
                      setInvitationToken(event.target.value);
                    }}
                  />
                </label>

                {invitation ? (
                  <div
                    className="rounded-xl px-4 py-3 text-sm"
                    style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
                  >
                    <strong>{invitation.organization.name}</strong>
                    <span className="ms-2" style={{ color: "var(--muted)" }}>
                      {invitation.role}
                    </span>
                  </div>
                ) : null}


                <button
                  className="w-full rounded-2xl px-4 py-3 font-semibold disabled:opacity-60"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  disabled={
                    busyAction === "register" ||
                    (invitationToken.trim().length > 0 && invitation === null)
                  }
                  onClick={() => {
                    if (!validate(invalidRegisterFields(registerForm, t))) return;
                    const profile = {
                      handle: registerForm.handle.trim(),
                      display_name: registerForm.display_name.trim(),
                      email: registerForm.email.trim(),
                      password: registerForm.password,
                    };
                    void runAction("register", async () => {
                      // Hold the redirect: recovery codes are offered first.
                      registeringRef.current = true;
                      try {
                        if (invitation) {
                          await signUpInvited({ ...profile, invitation_token: invitationToken.trim() });
                        } else {
                          // ADR-156: an invite kept on this device brought a new account.
                          markReferralNewAccount();
                          try {
                            await signUp({ ...profile, role: registerForm.role });
                          } catch (caught) {
                            markReferralNewAccount(false);
                            throw caught;
                          }
                        }
                        setOfferRecoveryCodes(true);
                      } catch (caught) {
                        registeringRef.current = false;
                        throw caught;
                      }
                    });
                  }}
                  type="button"
                >
                  {busyAction === "register" ? i18n("creatingAccountbaab5b8") : i18n("createAccountaaf3744")}
                </button>

                {/* ADR-184: the quiet way in for gyms and independent coaches. */}
                {invitationToken.trim().length === 0 ? (
                  <div className="text-center">
                    <BusinessSignUpLink />
                  </div>
                ) : null}
              </>
            ) : (
              <>
                {passwordResetDone ? <AuthNotice tone="success">{t("passwordChangedSignIn")}</AuthNotice> : null}

                <AuthField
                  label={t("identifierLabel")}
                  value={loginForm.identifier}
                  autoComplete="username"
                  errors={fieldErrors.identifier}
                  onChange={(identifier) => setLoginForm((f) => ({ ...f, identifier }))}
                />

                <AuthField
                  label={i18n("password8be3c94")}
                  value={loginForm.password}
                  type="password"
                  autoComplete="current-password"
                  errors={fieldErrors.password}
                  onChange={(password) => setLoginForm((f) => ({ ...f, password }))}
                />

                <div className="-mt-1 text-end">
                  <Link className="text-sm font-semibold" style={{ color: "var(--primary)" }} href="/forgot-password">
                    {t("forgotPasswordLink")}
                  </Link>
                </div>

                <button
                  className="w-full rounded-2xl px-4 py-3 font-semibold disabled:opacity-60"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  disabled={busyAction === "login"}
                  onClick={() => {
                    if (!validate(invalidLoginFields(loginForm, t))) return;
                    void runAction("login", async () => {
                      await signIn({ identifier: loginForm.identifier.trim(), password: loginForm.password });
                    });
                  }}
                  type="button"
                >
                  {busyAction === "login" ? i18n("signingInc66b2ad") : i18n("signInada2e9e")}
                </button>
              </>
            )}
          </div>

          {error ? (
            <p
              className="mt-4 rounded-2xl px-4 py-3 text-sm"
              style={{
                border: "1px solid color-mix(in srgb, var(--primary) 25%, transparent)",
                background: "color-mix(in srgb, var(--primary) 8%, transparent)",
                color: "var(--primary-strong)",
              }}
            >
              {error}
            </p>
          ) : null}
          </>}
        </div>
      </div>
    </main>
  );
}

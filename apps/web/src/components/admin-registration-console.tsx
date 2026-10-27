"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";

import { ApiError } from "@/api/client";
import {
  inspectInvitation,
  type AdminRegisterRequest,
  type InvitationInspection,
} from "@/api/auth";
import { useSession } from "@/components/session-provider";
import { useFragmentInvitationToken } from "@/lib/invitation-fragment";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { rememberSelectedOrganization } from "@/lib/organization-slug";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

type FieldErrors = Record<string, string[]>;

// ADR-187/204: the email already holds an account. Only the profile count is
// known before signing in; the person either proves the account with its
// password or signs in and accepts with a profile they have.
type ExistingAccount = { count: number | null; limit: number };

const DEFAULT_PROFILE_LIMIT = 3;

function existingAccountFrom(error: ApiError): ExistingAccount | null {
  const payload = error.payload as Record<string, unknown>;
  const code = payload.code;
  if (code !== "email_in_use" && code !== "profile_limit") return null;

  const limit = typeof payload.profile_limit === "number" ? payload.profile_limit : DEFAULT_PROFILE_LIMIT;
  if (code === "profile_limit") return { count: limit, limit };
  return { count: typeof payload.profile_count === "number" ? payload.profile_count : null, limit };
}

// ADR-187: the admin form still types one name, sent as the handle (the
// display name defaults to it).
type AdminRegisterForm = AdminRegisterRequest & { nickname: string };

const INITIAL_FORM: AdminRegisterForm = {
  nickname: "",
  password: "",
  email: "",
  invitation_token: "",
};

function validRegistrationPassword(password: string) {
  return password.length >= 4;
}

function flatFieldErrors(errors: Record<string, unknown> | undefined): FieldErrors {
  if (!errors) return {};

  return Object.fromEntries(
    Object.entries(errors).filter((entry): entry is [string, string[]] => {
      const [, messages] = entry;
      return Array.isArray(messages) && messages.every((message) => typeof message === "string");
    }),
  );
}

function summarizeFieldErrors(errors: FieldErrors, fieldLabels: Record<string, string>) {
  return Object.entries(errors)
    .map(([field, messages]) => `${fieldLabels[field] ?? field}: ${messages.join(", ")}`)
    .join(" ");
}

export function AdminRegistrationConsole() {
  const i18n = useUiTranslations();
  const router = useRouter();
  const searchParams = useSearchParams();
  const { signUpAdmin, acceptInvitation, signOut, status, currentUser } = useSession();
  // Set once this page creates the account, so only that sign-in moves on to
  // the invited organization.
  const [signedUpHere, setSignedUpHere] = useState(false);
  const [form, setForm] = useState<AdminRegisterForm>(() => ({
    ...INITIAL_FORM,
    invitation_token: searchParams.get("token") ?? "",
  }));
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [invitation, setInvitation] = useState<InvitationInspection | null>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  // ADR-209: an emailed invitation's link carries its token in the fragment;
  // it fills the code until the person edits it.
  const fragmentToken = useFragmentInvitationToken();
  const [tokenEdited, setTokenEdited] = useState(false);
  const invitationToken = form.invitation_token || (tokenEdited ? "" : fragmentToken);
  const [existingAccount, setExistingAccount] = useState<ExistingAccount | null>(null);

  useEffect(() => {
    const token = invitationToken.trim();
    if (token.length < 20) return;

    let cancelled = false;
    const timer = setTimeout(() => {
      void inspectInvitation(token)
        .then((result) => {
          if (cancelled) return;

          if (["owner", "admin"].includes(result.role)) {
            setInvitation(result);
            setError(null);
          } else {
            setInvitation(null);
            setError(i18n("apiErrorInvalidInvitation"));
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


  const validNickname = /^[\p{L}0-9_]{3,30}$/u.test(form.nickname);
  const validPassword = validRegistrationPassword(form.password);
  const fieldsComplete =
    form.nickname.trim().length > 0 &&
    form.email.trim().length > 0 &&
    form.password.length > 0 &&
    invitation !== null;
  const canSubmit = fieldsComplete && !busy;

  async function submit() {
    if (!canSubmit) return;
    if (!validNickname) {
      setError(i18n("usernameRules4b5de12"));
      setFieldErrors({ nickname: [i18n("usernameRules4b5de12")] });
      return;
    }
    if (!validPassword) {
      setError(i18n("passwordRules0c63f14"));
      setFieldErrors({ password: [i18n("passwordRules0c63f14")] });
      return;
    }

    setBusy(true);
    setError(null);
    setFieldErrors({});
    setExistingAccount(null);

    try {
      setSignedUpHere(true);
      await signUpAdmin({ ...form, invitation_token: invitationToken });
      if (invitation) {
        rememberSelectedOrganization(invitation.organization.slug);
        router.replace(`/org/${invitation.organization.slug}/admin`);
      }
    } catch (caught) {
      setSignedUpHere(false);
      const existing = caught instanceof ApiError ? existingAccountFrom(caught) : null;
      if (existing) {
        setExistingAccount(existing);
        setFieldErrors({ email: [], password: [""] });
      } else if (caught instanceof ApiError) {
        const nextFieldErrors = flatFieldErrors(caught.payload.errors);
        setFieldErrors(nextFieldErrors);
        setError(
          Object.keys(nextFieldErrors).length > 0
            ? summarizeFieldErrors(nextFieldErrors, {
                email: i18n("emailAddress"),
                nickname: i18n("nicknamece2bd99"),
                password: i18n("password8be3c94"),
                invitation_token: i18n("adminRegistrationCode"),
              })
            : localizeError(caught, i18n),
        );
      } else {
        setError(
          caught instanceof Error
            ? localizeError(caught, i18n)
            : i18n("unexpectedRequestFailurea7ffd06"),
        );
      }
    } finally {
      setBusy(false);
    }
  }

  async function acceptHere() {
    const token = invitationToken.trim();
    if (!invitation || busy) return;

    setBusy(true);
    setError(null);
    try {
      await acceptInvitation(token);
      rememberSelectedOrganization(invitation.organization.slug);
      router.replace(`/org/${invitation.organization.slug}/admin`);
    } catch (caught) {
      setError(caught instanceof Error ? localizeError(caught, i18n) : i18n("unexpectedRequestFailurea7ffd06"));
    } finally {
      setBusy(false);
    }
  }

  const signInHref = `/login?next=${encodeURIComponent(
    `/set-admin?token=${encodeURIComponent(invitationToken.trim())}`,
  )}`;

  // Opened while a profile is signed in (any tab of this browser), the page
  // asks before anything happens: accept with that profile (ADR-204), sign out
  // to create a separate one, or leave.
  if (status === "authenticated" && !signedUpHere) {
    const handle = currentUser?.handle ?? currentUser?.nickname ?? "";

    return (
      <main className="flex min-h-screen items-center justify-center px-6 py-10" style={{ background: "var(--bg)" }}>
        <section
          className="w-full max-w-md rounded-[2rem] p-7"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
            {i18n("adminRegistration")}
          </p>
          <h1 className="mt-2 text-2xl font-bold tracking-tight" style={{ color: "var(--text)" }}>
            {i18n("invitationSignedInAs", { handle })}
          </h1>
          <p className="mt-3 text-sm leading-6" style={{ color: "var(--muted)" }}>
            {invitation
              ? i18n("invitationForAnotherAccount", { organization: invitation.organization.name })
              : i18n("invitationForAnotherAccountGeneric")}
          </p>
          {error ? <ErrorNotice className="mt-4">{error}</ErrorNotice> : null}
          <div className="mt-6 space-y-3">
            {invitation ? (
              <button
                className="w-full rounded-2xl px-4 py-3 font-semibold disabled:opacity-50"
                disabled={busy}
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                type="button"
                onClick={() => void acceptHere()}
              >
                {busy ? i18n("invitationAccepting") : i18n("invitationAcceptAs", { handle })}
              </button>
            ) : null}
            <button
              className="w-full rounded-2xl px-4 py-3 font-semibold"
              style={
                invitation
                  ? { background: "transparent", color: "var(--text)", border: "1px solid var(--border)" }
                  : { background: "var(--primary)", color: "var(--primary-contrast)" }
              }
              type="button"
              onClick={() => signOut()}
            >
              {i18n("signOutAndContinue")}
            </button>
            <button
              className="w-full rounded-2xl px-4 py-3 font-semibold"
              style={{ background: "transparent", color: "var(--text)", border: "1px solid var(--border)" }}
              type="button"
              onClick={() => router.replace("/")}
            >
              {i18n("staySignedIn")}
            </button>
          </div>
        </section>
      </main>
    );
  }

  const nicknameErrors = fieldErrors.nickname ?? [];
  const emailErrors = fieldErrors.email ?? [];
  const passwordErrors = fieldErrors.password ?? [];
  const tokenErrors = fieldErrors.invitation_token ?? [];

  return (
    <main className="flex min-h-screen items-center justify-center px-6 py-10" style={{ background: "var(--bg)" }}>
      <section
        className="w-full max-w-md rounded-[2rem] p-7"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
          {i18n("adminRegistration")}
        </p>
        <h1 className="mt-2 text-2xl font-bold tracking-tight" style={{ color: "var(--text)" }}>
          {i18n("createAdminAccount")}
        </h1>
        <p className="mt-3 text-sm leading-6" style={{ color: "var(--muted)" }}>
          {i18n("adminRegistrationCodeHelp")}
        </p>

        <form
          className="mt-6 space-y-4"
          onSubmit={(event) => {
            event.preventDefault();
            void submit();
          }}
        >
          <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
            {i18n("nicknamece2bd99")}
            <input
              autoComplete="username"
              className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
              style={{
                background: "var(--bg)",
                border: `1px solid ${nicknameErrors.length > 0 ? "var(--danger)" : "var(--border)"}`,
                color: "var(--text)",
              }}
              value={form.nickname}
              onChange={(event) => {
                setError(null);
                setFieldErrors((current) => ({ ...current, nickname: [] }));
                setForm((current) => ({ ...current, nickname: event.target.value }));
              }}
            />
          </label>
          {nicknameErrors.length > 0 ? (
            <ErrorNotice variant="field" live="polite" className="-mt-3">
              {nicknameErrors.join(", ")}
            </ErrorNotice>
          ) : null}

          <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
            {i18n("emailAddress")}
            <input
              autoComplete="email"
              className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
              style={{
                background: "var(--bg)",
                border: `1px solid ${emailErrors.length > 0 ? "var(--danger)" : "var(--border)"}`,
                color: "var(--text)",
              }}
              type="email"
              value={form.email}
              onChange={(event) => {
                setError(null);
                setFieldErrors((current) => ({ ...current, email: [], password: [] }));
                setExistingAccount(null);
                setForm((current) => ({ ...current, email: event.target.value }));
              }}
            />
          </label>
          {emailErrors.length > 0 ? (
            <ErrorNotice variant="field" live="polite" className="-mt-3">
              {emailErrors.join(", ")}
            </ErrorNotice>
          ) : null}

          <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
            {i18n("password8be3c94")}
            <input
              aria-describedby="admin-registration-password-help"
              autoComplete="new-password"
              className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
              style={{
                background: "var(--bg)",
                border: `1px solid ${passwordErrors.length > 0 ? "var(--danger)" : "var(--border)"}`,
                color: "var(--text)",
              }}
              type="password"
              value={form.password}
              onChange={(event) => {
                setError(null);
                setFieldErrors((current) => ({ ...current, password: [] }));
                setForm((current) => ({ ...current, password: event.target.value }));
              }}
            />
          </label>
          <p id="admin-registration-password-help" className="-mt-3 text-xs" style={{ color: "var(--muted)" }}>
            {i18n("passwordRules0c63f14")} {i18n("adminPasswordExistingHint")}
          </p>

          {existingAccount ? (
            <ErrorNotice>
              <span className="block">
                {existingAccount.count !== null && existingAccount.count >= existingAccount.limit
                  ? i18n("adminEmailProfileLimit", { limit: existingAccount.limit })
                  : i18n("adminEmailHasProfiles", {
                      count: existingAccount.count ?? 1,
                      limit: existingAccount.limit,
                    })}
              </span>
              <span className="mt-2 flex flex-wrap gap-x-4 gap-y-1">
                <Link className="font-semibold underline" href={signInHref}>
                  {i18n("adminSignInToAccept")}
                </Link>
                <Link className="font-semibold underline" href="/forgot-password">
                  {i18n("adminForgotPassword")}
                </Link>
              </span>
            </ErrorNotice>
          ) : null}

          <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
            {i18n("adminRegistrationCode")}
            <input
              autoComplete="off"
              className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
              value={invitationToken}
              onChange={(event) => {
                setInvitation(null);
                setError(null);
                setFieldErrors((current) => ({ ...current, invitation_token: [] }));
                setTokenEdited(true);
                setForm((current) => ({ ...current, invitation_token: event.target.value }));
              }}
              style={{
                background: "var(--bg)",
                border: `1px solid ${tokenErrors.length > 0 ? "var(--danger)" : "var(--border)"}`,
                color: "var(--text)",
              }}
            />
          </label>
          {tokenErrors.length > 0 ? (
            <ErrorNotice variant="field" live="polite" className="-mt-3">
              {tokenErrors.join(", ")}
            </ErrorNotice>
          ) : null}

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

          {error ? (
            <ErrorNotice>{error}</ErrorNotice>
          ) : null}

          <button
            className="w-full rounded-2xl px-4 py-3 font-semibold disabled:opacity-50"
            disabled={!canSubmit}
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            type="submit"
          >
            {busy ? i18n("creatingAccountbaab5b8") : i18n("createAdminAccount")}
          </button>
        </form>
      </section>
    </main>
  );
}

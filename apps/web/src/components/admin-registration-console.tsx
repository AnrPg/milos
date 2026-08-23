"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { ApiError } from "@/api/client";
import {
  inspectInvitation,
  type AdminRegisterRequest,
  type InvitationInspection,
} from "@/api/auth";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { rememberSelectedOrganization } from "@/lib/organization-slug";

type FieldErrors = Record<string, string[]>;

const INITIAL_FORM: AdminRegisterRequest = {
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
  const { signUpAdmin, status } = useSession();
  const [form, setForm] = useState<AdminRegisterRequest>(() => ({
    ...INITIAL_FORM,
    invitation_token: searchParams.get("token") ?? "",
  }));
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [invitation, setInvitation] = useState<InvitationInspection | null>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});

  useEffect(() => {
    const token = form.invitation_token.trim();
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
  }, [form.invitation_token, i18n]);

  useEffect(() => {
    if (status !== "authenticated") return;

    if (invitation) {
      rememberSelectedOrganization(invitation.organization.slug);
      router.replace(`/org/${invitation.organization.slug}/admin`);
    } else {
      router.replace("/");
    }
  }, [invitation, router, status]);

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

    try {
      await signUpAdmin(form);
      if (invitation) {
        rememberSelectedOrganization(invitation.organization.slug);
        router.replace(`/org/${invitation.organization.slug}/admin`);
      }
    } catch (caught) {
      if (caught instanceof ApiError) {
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
            <p className="-mt-3 text-xs" style={{ color: "var(--danger)" }}>
              {nicknameErrors.join(", ")}
            </p>
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
                setFieldErrors((current) => ({ ...current, email: [] }));
                setForm((current) => ({ ...current, email: event.target.value }));
              }}
            />
          </label>
          {emailErrors.length > 0 ? (
            <p className="-mt-3 text-xs" style={{ color: "var(--danger)" }}>
              {emailErrors.join(", ")}
            </p>
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
            {i18n("passwordRules0c63f14")}
          </p>

          <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
            {i18n("adminRegistrationCode")}
            <input
              autoComplete="off"
              className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
              value={form.invitation_token}
              onChange={(event) => {
                setInvitation(null);
                setError(null);
                setFieldErrors((current) => ({ ...current, invitation_token: [] }));
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
            <p className="-mt-3 text-xs" style={{ color: "var(--danger)" }}>
              {tokenErrors.join(", ")}
            </p>
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
            <p
              className="rounded-xl px-3 py-2 text-sm"
              role="alert"
              style={{
                background: "color-mix(in srgb, var(--danger) 10%, transparent)",
                border: "1px solid color-mix(in srgb, var(--danger) 35%, transparent)",
                color: "var(--danger)",
              }}
            >
              {error}
            </p>
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

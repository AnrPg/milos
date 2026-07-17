"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { ApiError } from "@/api/client";
import type { AdminRegisterRequest } from "@/api/auth";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const INITIAL_FORM: AdminRegisterRequest = {
  nickname: "",
  password: "",
  admin_code: "",
};

export function AdminRegistrationConsole() {
  const i18n = useUiTranslations();
  const router = useRouter();
  const { signUpAdmin, status } = useSession();
  const [form, setForm] = useState<AdminRegisterRequest>(INITIAL_FORM);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (status === "authenticated") router.replace("/");
  }, [router, status]);

  const validNickname = /^[\p{L}0-9_]{3,30}$/u.test(form.nickname);
  const validPassword = form.password.length >= 4 && !/\s/u.test(form.password);
  const canSubmit = validNickname && validPassword && form.admin_code.length > 0 && !busy;

  async function submit() {
    if (!canSubmit) return;
    setBusy(true);
    setError(null);

    try {
      await signUpAdmin(form);
    } catch (caught) {
      setError(
        caught instanceof ApiError || caught instanceof Error
          ? localizeError(caught, i18n)
          : i18n("unexpectedRequestFailurea7ffd06"),
      );
    } finally {
      setBusy(false);
    }
  }

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

        <div className="mt-6 space-y-4">
          <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
            {i18n("nicknamece2bd99")}
            <input
              autoComplete="username"
              className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
              style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={form.nickname}
              onChange={(event) => setForm((current) => ({ ...current, nickname: event.target.value }))}
            />
          </label>

          <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
            {i18n("password8be3c94")}
            <input
              autoComplete="new-password"
              className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
              style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
              type="password"
              value={form.password}
              onChange={(event) => setForm((current) => ({ ...current, password: event.target.value }))}
            />
          </label>

          <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
            {i18n("adminRegistrationCode")}
            <input
              autoComplete="off"
              className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
              style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
              type="password"
              value={form.admin_code}
              onChange={(event) => setForm((current) => ({ ...current, admin_code: event.target.value }))}
            />
          </label>

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
            onClick={() => void submit()}
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            type="button"
          >
            {busy ? i18n("creatingAccountbaab5b8") : i18n("createAdminAccount")}
          </button>
        </div>
      </section>
    </main>
  );
}

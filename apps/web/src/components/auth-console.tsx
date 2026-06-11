"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";

import { ApiError } from "@/api/client";
import {
  type LoginRequest,
  type RegisterRequest,
} from "@/api/auth";
import { useSession } from "@/components/session-provider";

type Mode = "register" | "login";
type FieldErrors = Record<string, string[]>;

const initialRegister: RegisterRequest = {
  nickname: "",
  password: "",
  role: "member",
};

const initialLogin: LoginRequest = {
  nickname: "",
  password: "",
};

export function AuthConsole() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { currentUser, signIn, signOut, signUp, status } = useSession();
  const [mode, setMode] = useState<Mode>("login");
  const [registerForm, setRegisterForm] = useState<RegisterRequest>(initialRegister);
  const [loginForm, setLoginForm] = useState<LoginRequest>(initialLogin);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [busyAction, setBusyAction] = useState<string | null>(null);

  useEffect(() => {
    if (status !== "authenticated") return;
    router.replace(searchParams.get("next") || "/");
  }, [router, searchParams, status]);

  async function runAction(action: string, effect: () => Promise<void>) {
    setBusyAction(action);
    setError(null);
    setFieldErrors({});

    try {
      await effect();
    } catch (actionError) {
      if (actionError instanceof ApiError) {
        setError(actionError.message);
        setFieldErrors(actionError.payload.errors ?? {});
      } else {
        setError(actionError instanceof Error ? actionError.message : "Unexpected request failure");
      }
    } finally {
      setBusyAction(null);
    }
  }

  const registerNicknameErrors = fieldErrors.nickname ?? [];
  const registerPasswordErrors = fieldErrors.password ?? [];
  const registerRoleErrors = fieldErrors.role ?? [];

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "#0A0A0F" }}>
      <div className="mx-auto grid max-w-6xl gap-6 lg:grid-cols-[1.05fr_0.95fr]">
      <div className="rounded-[2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#d95d39" }}>
              Login
            </p>
            <h2 className="mt-2 text-2xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>Register and log in against the live API.</h2>
          </div>

          <div className="inline-flex rounded-full p-1 text-sm" style={{ background: "#1a1a28", border: "1px solid #2a2a3a" }}>
            <button
              className="rounded-full px-4 py-2 transition-colors"
              style={mode === "register" ? { background: "#d95d39", color: "#F0EDF8" } : { background: "transparent", color: "#55556a" }}
              onClick={() => setMode("register")}
              type="button"
            >
              Register
            </button>
            <button
              className="rounded-full px-4 py-2 transition-colors"
              style={mode === "login" ? { background: "#d95d39", color: "#F0EDF8" } : { background: "transparent", color: "#55556a" }}
              onClick={() => setMode("login")}
              type="button"
            >
              Login
            </button>
          </div>
        </div>

        <div className="mt-6 space-y-4">
          {mode === "register" ? (
            <>
              <label className="block text-sm font-medium" style={{ color: "#c0c0d8" }}>
                Nickname
                <input
                  className="mt-2 w-full rounded-2xl px-4 py-3 outline-none ring-0"
                  style={{ background: "#111118", border: "1px solid #1e1e2e", color: "#F0EDF8" }}
                  value={registerForm.nickname}
                  onChange={(event) =>
                    setRegisterForm((current: RegisterRequest) => ({
                      ...current,
                      nickname: event.target.value,
                    }))
                  }
                />
                {registerNicknameErrors.length > 0 ? (
                  <span className="mt-2 block text-sm" style={{ color: "#e07a5f" }}>
                    {registerNicknameErrors.join(", ")}
                  </span>
                ) : null}
              </label>
              <label className="block text-sm font-medium" style={{ color: "#c0c0d8" }}>
                Password
                <input
                  className="mt-2 w-full rounded-2xl px-4 py-3 outline-none ring-0"
                  style={{ background: "#111118", border: "1px solid #1e1e2e", color: "#F0EDF8" }}
                  type="password"
                  value={registerForm.password}
                  onChange={(event) =>
                    setRegisterForm((current: RegisterRequest) => ({
                      ...current,
                      password: event.target.value,
                    }))
                  }
                />
                {registerPasswordErrors.length > 0 ? (
                  <span className="mt-2 block text-sm" style={{ color: "#e07a5f" }}>
                    {registerPasswordErrors.join(", ")}
                  </span>
                ) : null}
              </label>
              <label className="block text-sm font-medium" style={{ color: "#c0c0d8" }}>
                Role
                <select
                  className="mt-2 w-full rounded-2xl px-4 py-3 outline-none ring-0"
                  style={{ background: "#111118", border: "1px solid #1e1e2e", color: "#F0EDF8" }}
                  value={registerForm.role}
                  onChange={(event) =>
                    setRegisterForm((current: RegisterRequest) => ({
                      ...current,
                      role: event.target.value as RegisterRequest["role"],
                    }))
                  }
                >
                  <option value="member">Member</option>
                  <option value="athlete">Athlete</option>
                </select>
                {registerRoleErrors.length > 0 ? (
                  <span className="mt-2 block text-sm" style={{ color: "#e07a5f" }}>
                    {registerRoleErrors.join(", ")}
                  </span>
                ) : null}
              </label>
              <button
                className="w-full rounded-2xl px-4 py-3 font-semibold disabled:opacity-60"
                style={{ background: "#d95d39", color: "#F0EDF8" }}
                disabled={busyAction === "register"}
                onClick={() =>
                  runAction("register", async () => {
                    await signUp(registerForm);
                  })
                }
                type="button"
              >
                {busyAction === "register" ? "Registering..." : "Create account"}
              </button>
            </>
          ) : (
            <>
              <label className="block text-sm font-medium" style={{ color: "#c0c0d8" }}>
                Nickname
                <input
                  className="mt-2 w-full rounded-2xl px-4 py-3 outline-none ring-0"
                  style={{ background: "#111118", border: "1px solid #1e1e2e", color: "#F0EDF8" }}
                  value={loginForm.nickname}
                  onChange={(event) =>
                    setLoginForm((current: LoginRequest) => ({
                      ...current,
                      nickname: event.target.value,
                    }))
                  }
                />
              </label>
              <label className="block text-sm font-medium" style={{ color: "#c0c0d8" }}>
                Password
                <input
                  className="mt-2 w-full rounded-2xl px-4 py-3 outline-none ring-0"
                  style={{ background: "#111118", border: "1px solid #1e1e2e", color: "#F0EDF8" }}
                  type="password"
                  value={loginForm.password}
                  onChange={(event) =>
                    setLoginForm((current: LoginRequest) => ({
                      ...current,
                      password: event.target.value,
                    }))
                  }
                />
              </label>
              <button
                className="w-full rounded-2xl px-4 py-3 font-semibold disabled:opacity-60"
                style={{ background: "#d95d39", color: "#F0EDF8" }}
                disabled={busyAction === "login"}
                onClick={() =>
                  runAction("login", async () => {
                    await signIn(loginForm);
                  })
                }
                type="button"
              >
                {busyAction === "login" ? "Signing in..." : "Sign in"}
              </button>
            </>
          )}
        </div>

        {error ? (
          <p className="mt-4 rounded-2xl px-4 py-3 text-sm" style={{ border: "1px solid rgba(217,93,57,0.25)", background: "rgba(217,93,57,0.08)", color: "#e07a5f" }}>
            {error}
          </p>
        ) : null}
      </div>

      <div className="rounded-[2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
        <div className="space-y-5">
          <div>
            <p className="text-sm uppercase tracking-[0.24em]" style={{ color: "#8888aa" }}>Phase Surface</p>
            <h3 className="mt-2 text-2xl font-semibold" style={{ color: "#F0EDF8" }}>Minimal authenticated flow for the implemented slices.</h3>
          </div>

          <div className="space-y-4 rounded-[1.5rem] p-4" style={{ border: "1px solid #1a1a28", background: "rgba(255,255,255,0.03)" }}>
            <div>
              <p className="text-xs uppercase tracking-[0.2em]" style={{ color: "#8888aa" }}>Session posture</p>
              <p className="mt-2 text-sm" style={{ color: "#c0c0d8" }}>
                {status === "authenticated"
                  ? "Authenticated session is persisted locally and restored on refresh."
                  : "No active session yet."}
              </p>
            </div>
            <div>
              <p className="text-xs uppercase tracking-[0.2em]" style={{ color: "#8888aa" }}>Reload behavior</p>
              <p className="mt-2 text-sm" style={{ color: "#c0c0d8" }}>
                Refresh now restores the session instead of dropping credentials.
              </p>
            </div>
          </div>

          {status === "authenticated" ? (
            <div className="grid gap-3 sm:grid-cols-2">
              <Link
                className="rounded-2xl px-4 py-3 text-center text-sm font-semibold"
                style={{ border: "1px solid #2a2a3a", background: "#1a1a28", color: "#F0EDF8" }}
                href="/"
              >
                Continue to landing page
              </Link>

              <button
                className="rounded-2xl px-4 py-3 text-sm font-semibold"
                style={{ border: "1px solid #2a2a3a", background: "transparent", color: "#c0c0d8" }}
                onClick={signOut}
                type="button"
              >
                Log out
              </button>
            </div>
          ) : null}

          <div className="rounded-[1.5rem] p-4" style={{ border: "1px solid #1a1a28", background: "rgba(0,0,0,0.2)" }}>
            <p className="text-xs uppercase tracking-[0.2em]" style={{ color: "#8888aa" }}>Authenticated user</p>
            {currentUser ? (
              <dl className="mt-3 space-y-2 text-sm" style={{ color: "#c0c0d8" }}>
                <div className="flex items-center justify-between gap-4">
                  <dt style={{ color: "#8888aa" }}>ID</dt>
                  <dd className="break-all text-right">{currentUser.id}</dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt style={{ color: "#8888aa" }}>Nickname</dt>
                  <dd>{currentUser.nickname}</dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt style={{ color: "#8888aa" }}>Role</dt>
                  <dd>{currentUser.role}</dd>
                </div>
              </dl>
            ) : (
              <p className="mt-3 text-sm" style={{ color: "#55556a" }}>
                No authenticated user loaded yet.
              </p>
            )}
          </div>
        </div>
      </div>
      </div>
    </main>
  );
}

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
  const [mode, setMode] = useState<Mode>("register");
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
    <main className="min-h-screen bg-[radial-gradient(circle_at_top_left,rgba(217,93,57,0.14),transparent_24%),linear-gradient(180deg,#fffdf8_0%,#f5ede3_100%)] px-6 py-10 md:px-10 md:py-14">
      <div className="mx-auto grid max-w-6xl gap-6 lg:grid-cols-[1.05fr_0.95fr]">
      <div className="rounded-[2rem] border border-black/10 bg-surface p-6 shadow-[0_20px_60px_rgba(20,40,29,0.08)]">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.24em] text-accent-strong">
              Login
            </p>
            <h2 className="mt-2 text-2xl font-semibold tracking-tight">Register and log in against the live API.</h2>
          </div>

          <div className="inline-flex rounded-full border border-black/10 bg-black/5 p-1 text-sm">
            <button
              className={`rounded-full px-4 py-2 ${mode === "register" ? "bg-foreground text-white" : "text-black/70"}`}
              onClick={() => setMode("register")}
              type="button"
            >
              Register
            </button>
            <button
              className={`rounded-full px-4 py-2 ${mode === "login" ? "bg-foreground text-white" : "text-black/70"}`}
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
              <label className="block text-sm font-medium">
                Nickname
                <input
                  className="mt-2 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none ring-0"
                  value={registerForm.nickname}
                  onChange={(event) =>
                    setRegisterForm((current: RegisterRequest) => ({
                      ...current,
                      nickname: event.target.value,
                    }))
                  }
                />
                {registerNicknameErrors.length > 0 ? (
                  <span className="mt-2 block text-sm text-accent-strong">
                    {registerNicknameErrors.join(", ")}
                  </span>
                ) : null}
              </label>
              <label className="block text-sm font-medium">
                Password
                <input
                  className="mt-2 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none ring-0"
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
                  <span className="mt-2 block text-sm text-accent-strong">
                    {registerPasswordErrors.join(", ")}
                  </span>
                ) : null}
              </label>
              <label className="block text-sm font-medium">
                Role
                <select
                  className="mt-2 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none ring-0"
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
                  <span className="mt-2 block text-sm text-accent-strong">
                    {registerRoleErrors.join(", ")}
                  </span>
                ) : null}
              </label>
              <button
                className="w-full rounded-2xl bg-accent px-4 py-3 font-semibold text-white disabled:opacity-60"
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
              <label className="block text-sm font-medium">
                Nickname
                <input
                  className="mt-2 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none ring-0"
                  value={loginForm.nickname}
                  onChange={(event) =>
                    setLoginForm((current: LoginRequest) => ({
                      ...current,
                      nickname: event.target.value,
                    }))
                  }
                />
              </label>
              <label className="block text-sm font-medium">
                Password
                <input
                  className="mt-2 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none ring-0"
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
                className="w-full rounded-2xl bg-foreground px-4 py-3 font-semibold text-white disabled:opacity-60"
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
          <p className="mt-4 rounded-2xl border border-[#d95d39]/20 bg-[#d95d39]/10 px-4 py-3 text-sm text-accent-strong">
            {error}
          </p>
        ) : null}
      </div>

      <div className="rounded-[2rem] bg-[linear-gradient(180deg,#14281d_0%,#274230_100%)] p-6 text-white shadow-[0_24px_80px_rgba(20,40,29,0.18)]">
        <div className="space-y-5">
          <div>
            <p className="text-sm uppercase tracking-[0.24em] text-white/65">Phase Surface</p>
            <h3 className="mt-2 text-2xl font-semibold">Minimal authenticated flow for the implemented slices.</h3>
          </div>

          <div className="space-y-4 rounded-[1.5rem] border border-white/10 bg-white/5 p-4">
            <div>
              <p className="text-xs uppercase tracking-[0.2em] text-white/60">Session posture</p>
              <p className="mt-2 text-sm text-white/85">
                {status === "authenticated"
                  ? "Authenticated session is persisted locally and restored on refresh."
                  : "No active session yet."}
              </p>
            </div>
            <div>
              <p className="text-xs uppercase tracking-[0.2em] text-white/60">Reload behavior</p>
              <p className="mt-2 text-sm text-white/85">
                Refresh now restores the session instead of dropping credentials.
              </p>
            </div>
          </div>

          {status === "authenticated" ? (
            <div className="grid gap-3 sm:grid-cols-2">
              <Link
                className="rounded-2xl border border-white/15 bg-white/10 px-4 py-3 text-center text-sm font-semibold"
                href="/"
              >
                Continue to landing page
              </Link>

              <button
                className="rounded-2xl border border-white/15 bg-transparent px-4 py-3 text-sm font-semibold text-white/85"
                onClick={signOut}
                type="button"
              >
                Log out
              </button>
            </div>
          ) : null}

          <div className="rounded-[1.5rem] border border-white/10 bg-black/15 p-4">
            <p className="text-xs uppercase tracking-[0.2em] text-white/60">Authenticated user</p>
            {currentUser ? (
              <dl className="mt-3 space-y-2 text-sm text-white/90">
                <div className="flex items-center justify-between gap-4">
                  <dt className="text-white/60">ID</dt>
                  <dd className="break-all text-right">{currentUser.id}</dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt className="text-white/60">Nickname</dt>
                  <dd>{currentUser.nickname}</dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt className="text-white/60">Role</dt>
                  <dd>{currentUser.role}</dd>
                </div>
              </dl>
            ) : (
              <p className="mt-3 text-sm text-white/70">
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

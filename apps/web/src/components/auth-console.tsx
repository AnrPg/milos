"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { ApiError } from "@/api/client";
import { checkNicknameAvailable, type LoginRequest, type RegisterRequest } from "@/api/auth";
import { getAvatarUploadUrl, updateAvatar } from "@/api/profile";
import { useSession } from "@/components/session-provider";

type Mode = "register" | "login";
type FieldErrors = Record<string, string[]>;

const initialRegister: RegisterRequest = { nickname: "", password: "", role: "member" };
const initialLogin: LoginRequest = { nickname: "", password: "" };

function flatFieldErrors(errors: Record<string, unknown> | undefined): FieldErrors {
  if (!errors) return {};
  return Object.fromEntries(
    Object.entries(errors).filter((entry): entry is [string, string[]] => {
      const [, messages] = entry;
      return Array.isArray(messages) && messages.every((m) => typeof m === "string");
    }),
  );
}

export function AuthConsole({ initialMode = "login" }: { initialMode?: Mode }) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const searchParams = useSearchParams();
  const { signIn, signUp, status, tokens } = useSession();

  const [mode, setMode] = useState<Mode>(initialMode);
  const [registerForm, setRegisterForm] = useState<RegisterRequest>(initialRegister);
  const [loginForm, setLoginForm] = useState<LoginRequest>(initialLogin);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const [nicknameStatus, setNicknameStatus] = useState<"idle" | "checking" | "available" | "taken">("idle");

  // Stored in a ref so the post-registration upload effect doesn't need it as a dep
  const pendingAvatarRef = useRef<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (status !== "authenticated") return;
    router.replace(searchParams.get("next") || "/");
  }, [router, searchParams, status]);

  // Debounced nickname availability check
  useEffect(() => {
    if (mode !== "register") return;
    const nickname = registerForm.nickname.trim();
    if (nickname.length < 3) {
      queueMicrotask(() => setNicknameStatus("idle"));
      return;
    }
    queueMicrotask(() => setNicknameStatus("checking"));
    const timer = setTimeout(async () => {
      try {
        const { available } = await checkNicknameAvailable(nickname);
        setNicknameStatus(available ? "available" : "taken");
      } catch {
        setNicknameStatus("idle");
      }
    }, 500);
    return () => clearTimeout(timer);
  }, [registerForm.nickname, mode]);

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
      if (err instanceof ApiError) {
        setError(err.message);
        setFieldErrors(flatFieldErrors(err.payload.errors));
      } else {
        setError(err instanceof Error ? err.message : i18n("unexpectedRequestFailurea7ffd06"));
      }
    } finally {
      setBusyAction(null);
    }
  }

  const nicknameErrors = fieldErrors.nickname ?? [];
  const passwordErrors = fieldErrors.password ?? [];
  const roleErrors = fieldErrors.role ?? [];

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
          {/* Mode toggle */}
          <div className="mb-7 flex justify-center">
            <div
              className="inline-flex rounded-full p-1 text-sm"
              style={{ background: "var(--border)", border: "1px solid var(--border-strong)" }}
            >
              <button
                className="rounded-full px-5 py-2 transition-colors"
                style={
                  mode === "register"
                    ? { background: "var(--primary)", color: "var(--text)" }
                    : { background: "transparent", color: "var(--dim)" }
                }
                onClick={() => setMode("register")}
                type="button"
              >
                {i18n("registerd672995")}
              </button>
              <button
                className="rounded-full px-5 py-2 transition-colors"
                style={
                  mode === "login"
                    ? { background: "var(--primary)", color: "var(--text)" }
                    : { background: "transparent", color: "var(--dim)" }
                }
                onClick={() => setMode("login")}
                type="button"
              >
                {i18n("login4e5a289")}
              </button>
            </div>
          </div>

          <div className="mb-6 text-center">
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
              {i18n("milosTraining5b1a1c1")}
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

                {/* Nickname */}
                <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                  <div className="flex items-center justify-between">
                    <span>{i18n("nicknamece2bd99")}</span>
                    {nicknameStatus === "checking" && (
                      <span className="text-xs" style={{ color: "var(--dim)" }}>{i18n("checking820d600")}</span>
                    )}
                    {nicknameStatus === "available" && (
                      <span className="text-xs font-semibold" style={{ color: "var(--success, #4ade80)" }}>{i18n("availableaeed20b")}</span>
                    )}
                    {nicknameStatus === "taken" && (
                      <span className="text-xs font-semibold" style={{ color: "var(--primary-strong)" }}>{i18n("alreadyTakena92fd32")}</span>
                    )}
                  </div>
                  <input
                    className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
                    style={{
                      background: "var(--bg)",
                      border: `1px solid ${nicknameStatus === "available" ? "var(--success, #4ade80)" : nicknameStatus === "taken" ? "var(--primary-strong)" : "var(--border)"}`,
                      color: "var(--text)",
                    }}
                    value={registerForm.nickname}
                    placeholder={i18n("chooseAUniqueNickname4b5894d")}
                    onChange={(e) =>
                      setRegisterForm((f) => ({ ...f, nickname: e.target.value }))
                    }
                  />
                  {nicknameErrors.length > 0 && (
                    <span className="mt-1.5 block text-xs" style={{ color: "var(--primary-strong)" }}>
                      {nicknameErrors.join(", ")}
                    </span>
                  )}
                </label>

                {/* Password */}
                <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                  {i18n("password8be3c94")}
                  <input
                    className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
                    style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
                    type="password"
                    value={registerForm.password}
                    placeholder={i18n("atLeast8Characters1fe494b")}
                    onChange={(e) =>
                      setRegisterForm((f) => ({ ...f, password: e.target.value }))
                    }
                  />
                  {passwordErrors.length > 0 && (
                    <span className="mt-1.5 block text-xs" style={{ color: "var(--primary-strong)" }}>
                      {passwordErrors.join(", ")}
                    </span>
                  )}
                </label>

                {/* Role cards */}
                <div>
                  <p className="mb-2 text-sm font-medium" style={{ color: "var(--text-soft)" }}>{i18n("iAmA5191365")}</p>
                  <div className="grid grid-cols-2 gap-3">
                    {(
                      [
                        { value: "member", label: i18n("gymMemberfeecab7"), description: i18n("trainWithAStructuredProgrammeeca768c") },
                        { value: "athlete", label: i18n("autonomousAthlete89280a4"), description: i18n("selfDirectedTraininge36a9cb") },
                      ] as const
                    ).map(({ value, label, description }) => {
                      const selected = registerForm.role === value;
                      return (
                        <button
                          key={value}
                          type="button"
                          className="rounded-2xl p-4 text-left transition-all"
                          style={{
                            background: selected
                              ? "color-mix(in srgb, var(--primary) 12%, transparent)"
                              : "var(--bg)",
                            border: selected
                              ? "1.5px solid var(--primary)"
                              : "1.5px solid var(--border)",
                          }}
                          onClick={() => setRegisterForm((f) => ({ ...f, role: value }))}
                        >
                          <p className="text-sm font-semibold" style={{ color: selected ? "var(--primary)" : "var(--text)" }}>
                            {label}
                          </p>
                          <p className="mt-1 text-xs leading-snug" style={{ color: "var(--dim)" }}>
                            {description}
                          </p>
                        </button>
                      );
                    })}
                  </div>
                  {roleErrors.length > 0 && (
                    <span className="mt-1.5 block text-xs" style={{ color: "var(--primary-strong)" }}>
                      {roleErrors.join(", ")}
                    </span>
                  )}
                </div>

                <button
                  className="w-full rounded-2xl px-4 py-3 font-semibold disabled:opacity-60"
                  style={{ background: "var(--primary)", color: "var(--text)" }}
                  disabled={busyAction === "register"}
                  onClick={() => runAction("register", async () => { await signUp(registerForm); })}
                  type="button"
                >
                  {busyAction === "register" ? i18n("creatingAccountbaab5b8") : i18n("createAccountaaf3744")}
                </button>
              </>
            ) : (
              <>
                {/* Nickname */}
                <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                  {i18n("nicknamece2bd99")}
                  <input
                    className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
                    style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
                    value={loginForm.nickname}
                    onChange={(e) => setLoginForm((f) => ({ ...f, nickname: e.target.value }))}
                  />
                </label>

                {/* Password */}
                <label className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                  {i18n("password8be3c94")}
                  <input
                    className="mt-2 w-full rounded-2xl px-4 py-3 outline-none"
                    style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
                    type="password"
                    value={loginForm.password}
                    onChange={(e) => setLoginForm((f) => ({ ...f, password: e.target.value }))}
                  />
                </label>

                <button
                  className="w-full rounded-2xl px-4 py-3 font-semibold disabled:opacity-60"
                  style={{ background: "var(--primary)", color: "var(--text)" }}
                  disabled={busyAction === "login"}
                  onClick={() => runAction("login", async () => { await signIn(loginForm); })}
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
        </div>
      </div>
    </main>
  );
}

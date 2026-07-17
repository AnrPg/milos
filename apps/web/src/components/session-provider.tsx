"use client";




import {useUiTranslations} from "@/i18n/ui";
import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import {
  fetchCurrentUser,
  loginUser,
  logoutSession,
  refreshSession,
  registerAdminUser,
  registerUser,
  type AdminRegisterRequest,
  type AuthTokens,
  type CurrentUser,
  type LoginRequest,
  type RegisterRequest,
} from "@/api/auth";
import {
  broadcastSessionSignOut,
  SESSION_EXPIRED_EVENT,
  SESSION_UPDATED_EVENT,
  setApiSessionUser,
} from "@/api/client";
import {
  clearWorkoutCache,
  clearBrowserPushSubscription,
  setWorkoutCacheUser,
} from "@/lib/push-subscription";
import { resetRealtimeSocket } from "@/lib/realtime";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { isAppLocale, persistLocaleCookie } from "@/i18n/locales";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

type SessionStatus = "loading" | "guest" | "authenticated";

type SessionContextValue = {
  status: SessionStatus;
  tokens: AuthTokens | null;
  currentUser: CurrentUser | null;
  signIn: (payload: LoginRequest) => Promise<CurrentUser>;
  signUp: (payload: RegisterRequest) => Promise<CurrentUser>;
  signUpAdmin: (payload: AdminRegisterRequest) => Promise<CurrentUser>;
  rotate: () => Promise<void>;
  signOut: () => void;
};

type SessionExpiredState = {
  title: string;
  message: string;
  instructions: string[];
} | null;

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: React.ReactNode }) {
  
  const tSession = useTranslations("Session");
  const tCommon = useTranslations("Common");
  const [status, setStatus] = useState<SessionStatus>("loading");
  const [tokens, setTokens] = useState<AuthTokens | null>(null);
  const [currentUser, setCurrentUser] = useState<CurrentUser | null>(null);
  const [sessionExpired, setSessionExpired] = useState<SessionExpiredState>(null);
  const accessTokenRef = useRef<string | undefined>(undefined);

  useEffect(() => {
    accessTokenRef.current = tokens?.access_token;
  }, [tokens?.access_token]);

  function commitSession(
    nextTokens: AuthTokens,
    user: CurrentUser,
  ) {
    void setWorkoutCacheUser(user.id);
    setTokens(nextTokens);
    setCurrentUser(user);
    setStatus("authenticated");
    setSessionExpired(null);
    setApiSessionUser(user);

    if (isAppLocale(user.preferred_locale)) {
      const localeChanged = document.documentElement.lang !== user.preferred_locale;
      persistLocaleCookie(user.preferred_locale);
      if (localeChanged) window.location.reload();
    }
  }

  function resetSession(accessTokenForCleanup?: string | null) {
    resetRealtimeSocket();
    void setWorkoutCacheUser(null);
    setTokens(null);
    setCurrentUser(null);
    setStatus("guest");
    setApiSessionUser(null);

    void clearBrowserPushSubscription(accessTokenForCleanup);
  }

  async function establishSession(issuedTokens: AuthTokens) {
    const user = await fetchCurrentUser(issuedTokens.access_token);
    commitSession(issuedTokens, user);
    return user;
  }

  async function signIn(payload: LoginRequest) {
    const issuedTokens = await loginUser(payload);
    return establishSession(issuedTokens);
  }

  async function signUp(payload: RegisterRequest) {
    const issuedTokens = await registerUser(payload);
    return establishSession(issuedTokens);
  }

  async function signUpAdmin(payload: AdminRegisterRequest) {
    const issuedTokens = await registerAdminUser(payload);
    return establishSession(issuedTokens);
  }

  async function rotate() {
    if (!tokens) return;

    const refreshedTokens = await refreshSession();
    if (!refreshedTokens?.access_token) {
      resetSession(tokens.access_token);
      return;
    }
    const user = currentUser ?? (await fetchCurrentUser(refreshedTokens.access_token));
    commitSession(refreshedTokens, user);
  }

  function signOut() {
    void logoutSession().catch(() => undefined);
    broadcastSessionSignOut();
    resetSession(tokens?.access_token);
  }

  const showSessionExpiredPopup = useCallback(() => {
    setSessionExpired({
      title: tSession("expiredTitle"),
      message: tSession("expiredMessage"),
      instructions: [
        tSession("keepOpen"),
        tSession("doNotRefresh"),
        tSession("loginNewTabInstruction"),
      ],
    });
  }, [tSession]);

  useEffect(() => {
    let cancelled = false;

    async function bootstrap() {
      try {
        const refreshedTokens = await refreshSession();
        if (!refreshedTokens?.access_token) {
          if (!cancelled) setStatus("guest");
          return;
        }
        const user = await fetchCurrentUser(refreshedTokens.access_token);
        if (cancelled) return;
        commitSession(refreshedTokens, user);
      } catch {
        if (!cancelled) setStatus("guest");
      }
    }

    void bootstrap();

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    function handleUserSync(event: Event) {
      const detail = (event as CustomEvent<UserSyncDetail>).detail;

      if (detail.scopes.includes("session")) {
        resetSession(accessTokenRef.current);
      } else if (
        detail.scopes.some((scope) =>
          ["finance", "workouts", "execution", "entitlements"].includes(scope),
        )
      ) {
        void clearWorkoutCache();
      }
    }

    window.addEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);

    return () => {
      window.removeEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
    };
  }, []);

  useEffect(() => {
    async function handleSessionUpdate(event: Event) {
      const customEvent = event as CustomEvent<{
        tokens: AuthTokens | null;
        currentUser: CurrentUser | null;
      }>;

      if (!customEvent.detail.tokens) {
        resetSession(accessTokenRef.current);
        return;
      }

      try {
        const user =
          customEvent.detail.currentUser ??
          (await fetchCurrentUser(customEvent.detail.tokens.access_token));
        commitSession(customEvent.detail.tokens, user);
      } catch {
        resetSession(accessTokenRef.current);
      }
    }

    window.addEventListener(SESSION_UPDATED_EVENT, handleSessionUpdate as EventListener);

    return () => {
      window.removeEventListener(SESSION_UPDATED_EVENT, handleSessionUpdate as EventListener);
    };
  }, []);

  useEffect(() => {
    function handleSessionExpired() {
      showSessionExpiredPopup();
    }

    window.addEventListener(SESSION_EXPIRED_EVENT, handleSessionExpired as EventListener);

    return () => {
      window.removeEventListener(SESSION_EXPIRED_EVENT, handleSessionExpired as EventListener);
    };
  }, [showSessionExpiredPopup]);

  return (
    <SessionContext.Provider
      value={{
        status,
        tokens,
        currentUser,
        signIn,
        signUp,
        signUpAdmin,
        rotate,
        signOut,
      }}
    >
      {children}
      {sessionExpired ? (
        <SessionExpiredDialog
          state={sessionExpired}
          onDismiss={() => setSessionExpired(null)}
          dismissLabel={tCommon("dismiss")}
          requiredLabel={tSession("required")}
          openLoginLabel={tSession("openLogin")}
        />
      ) : null}
    </SessionContext.Provider>
  );
}

function SessionExpiredDialog({
  state,
  onDismiss,
  dismissLabel,
  requiredLabel,
  openLoginLabel,
}: {
  state: NonNullable<SessionExpiredState>;
  onDismiss: () => void;
  dismissLabel: string;
  requiredLabel: string;
  openLoginLabel: string;
}) {
  
  const dialogRef = useModalFocusTrap<HTMLDivElement>(onDismiss);

  return (
    <div
      className="fixed inset-0 z-[100] flex items-end justify-center p-4 sm:items-center"
      style={{ background: "rgba(0,0,0,0.7)" }}
      role="presentation"
      onMouseDown={(event) => {
        if (event.currentTarget === event.target) onDismiss();
      }}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="session-expired-title"
        tabIndex={-1}
        className="w-full max-w-lg rounded-[28px] border p-6 shadow-[0_24px_80px_rgba(0,0,0,0.55)]"
        style={{ background: "var(--panel)", borderColor: "var(--border-strong)", color: "var(--text)" }}
      >
            <div className="text-xs font-black uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>
              {requiredLabel}
            </div>
            <h2 id="session-expired-title" className="mt-2 text-2xl font-bold">{state.title}</h2>
            <p className="mt-3 text-sm leading-6" style={{ color: "var(--text-soft)" }}>
              {state.message}
            </p>

            <div
              className="mt-4 rounded-2xl border px-4 py-3 text-sm"
              style={{ background: "var(--panel-muted)", borderColor: "var(--border-strong)", color: "var(--text-soft)" }}
            >
              {state.instructions.map((instruction) => (
                <div key={instruction} className="flex gap-2">
                  <span style={{ color: "var(--warning)" }}>•</span>
                  <span>{instruction}</span>
                </div>
              ))}
            </div>

            <div className="mt-5 flex flex-col gap-3 sm:flex-row">
              <button
                type="button"
                onClick={() => window.open("/login", "_blank", "noopener,noreferrer")}
                className="flex-1 rounded-2xl px-4 py-3 text-sm font-bold"
                style={{ background: "var(--primary)", color: "var(--bg)" }}
              >
                {openLoginLabel}
              </button>
              <button
                type="button"
                onClick={onDismiss}
                className="flex-1 rounded-2xl border px-4 py-3 text-sm font-semibold"
                style={{ borderColor: "var(--border-strong)", color: "var(--text-soft)" }}
              >
                {dismissLabel}
              </button>
            </div>
      </div>
    </div>
  );
}

export function useSession() {
  const i18n = useUiTranslations();
  const context = useContext(SessionContext);

  if (!context) {
    throw new Error(i18n("usesessionMustBeUsedWithinSessionprovider83b2d13"));
  }

  return context;
}

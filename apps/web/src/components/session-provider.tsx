"use client";

import { createContext, useContext, useEffect, useRef, useState } from "react";

import {
  fetchCurrentUser,
  loginUser,
  refreshSession,
  registerUser,
  type AuthTokens,
  type CurrentUser,
  type LoginRequest,
  type RegisterRequest,
} from "@/api/auth";
import { ApiError, SESSION_EXPIRED_EVENT, SESSION_UPDATED_EVENT } from "@/api/client";
import {
  clearBrowserPushSubscription,
  setWorkoutCacheUser,
} from "@/lib/push-subscription";
import {
  clearStoredSession,
  parseStoredSession,
  readStoredSession,
  SESSION_STORAGE_KEY,
  writeStoredSession,
} from "@/lib/session-storage";
import { resetRealtimeSocket } from "@/lib/realtime";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";

type SessionStatus = "loading" | "guest" | "authenticated";

type SessionContextValue = {
  status: SessionStatus;
  tokens: AuthTokens | null;
  currentUser: CurrentUser | null;
  signIn: (payload: LoginRequest) => Promise<CurrentUser>;
  signUp: (payload: RegisterRequest) => Promise<CurrentUser>;
  rotate: () => Promise<void>;
  signOut: () => void;
};

type SessionExpiredState = {
  title: string;
  message: string;
  instructions: string[];
} | null;

const SessionContext = createContext<SessionContextValue | null>(null);

type SessionPersistenceOptions = {
  persist?: boolean;
};

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [status, setStatus] = useState<SessionStatus>("loading");
  const [tokens, setTokens] = useState<AuthTokens | null>(null);
  const [currentUser, setCurrentUser] = useState<CurrentUser | null>(null);
  const [sessionExpired, setSessionExpired] = useState<SessionExpiredState>(null);
  const accessTokenRef = useRef<string | undefined>(undefined);
  const refreshTokenRef = useRef<string | undefined>(undefined);
  const currentUserRef = useRef<CurrentUser | null>(null);

  useEffect(() => {
    accessTokenRef.current = tokens?.access_token;
    refreshTokenRef.current = tokens?.refresh_token;
  }, [tokens?.access_token, tokens?.refresh_token]);

  useEffect(() => {
    currentUserRef.current = currentUser;
  }, [currentUser]);

  function commitSession(
    nextTokens: AuthTokens,
    user: CurrentUser,
    options: SessionPersistenceOptions = {},
  ) {
    void setWorkoutCacheUser(user.id);
    setTokens(nextTokens);
    setCurrentUser(user);
    setStatus("authenticated");
    setSessionExpired(null);

    if (options.persist !== false) {
      writeStoredSession({ tokens: nextTokens, currentUser: user });
    }
  }

  function resetSession(
    accessTokenForCleanup?: string | null,
    options: SessionPersistenceOptions = {},
  ) {
    resetRealtimeSocket();
    void setWorkoutCacheUser(null);
    setTokens(null);
    setCurrentUser(null);
    setStatus("guest");

    if (options.persist !== false) {
      clearStoredSession();
    }

    void clearBrowserPushSubscription(accessTokenForCleanup);
  }

  function syncFromStoredSession() {
    const stored = readStoredSession();

    if (!stored) {
      if (accessTokenRef.current || currentUserRef.current) {
        resetSession(accessTokenRef.current, { persist: false });
      }

      return;
    }

    const sameTokens =
      stored.tokens.access_token === accessTokenRef.current &&
      stored.tokens.refresh_token === refreshTokenRef.current;
    const sameUser = stored.currentUser.id === currentUserRef.current?.id;

    if (sameTokens && sameUser) {
      setSessionExpired(null);
      return;
    }

    commitSession(stored.tokens, stored.currentUser, { persist: false });
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

  async function rotate() {
    if (!tokens) return;

    const refreshedTokens = await refreshSession({ refresh_token: tokens.refresh_token });
    const user = currentUser ?? (await fetchCurrentUser(refreshedTokens.access_token));
    commitSession(refreshedTokens, user);
  }

  function signOut() {
    resetSession(tokens?.access_token);
  }

  function showSessionExpiredPopup() {
    setSessionExpired({
      title: "Session expired",
      message:
        "Your sign-in session could not be refreshed. You are signed out until you authenticate again.",
      instructions: [
        "Keep this tab open if you have unsaved draft changes on screen.",
        "Do not refresh this page before signing in again, because local in-memory edits may be lost.",
        "Open the login page in a new tab, sign in, then return here and retry Save or Publish.",
      ],
    });
  }

  useEffect(() => {
    let cancelled = false;

    async function bootstrap() {
      const stored = readStoredSession();

      if (!stored) {
        if (!cancelled) setStatus("guest");
        return;
      }

      try {
        const user = await fetchCurrentUser(stored.tokens.access_token);
        if (cancelled) return;
        commitSession(stored.tokens, user);
      } catch (error) {
        if (!(error instanceof ApiError) || error.status !== 401) {
          if (!cancelled) commitSession(stored.tokens, stored.currentUser);
          return;
        }

        try {
          const refreshedTokens = await refreshSession({ refresh_token: stored.tokens.refresh_token });
          const user = await fetchCurrentUser(refreshedTokens.access_token);
          if (cancelled) return;
          commitSession(refreshedTokens, user);
        } catch {
          if (!cancelled) {
            const latest = readStoredSession();

            if (latest?.tokens.refresh_token && latest.tokens.refresh_token !== stored.tokens.refresh_token) {
              commitSession(latest.tokens, latest.currentUser, { persist: false });
              return;
            }

            resetSession(stored.tokens.access_token);
            showSessionExpiredPopup();
          }
        }
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
      }
    }

    window.addEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);

    return () => {
      window.removeEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
    };
  }, []);

  useEffect(() => {
    function handleSessionUpdate(event: Event) {
      const customEvent = event as CustomEvent<{
        tokens: AuthTokens | null;
        currentUser: CurrentUser | null;
      }>;

      if (!customEvent.detail.tokens || !customEvent.detail.currentUser) {
        resetSession(accessTokenRef.current, { persist: false });
        return;
      }

      commitSession(customEvent.detail.tokens, customEvent.detail.currentUser, { persist: false });
    }

    window.addEventListener(SESSION_UPDATED_EVENT, handleSessionUpdate as EventListener);

    return () => {
      window.removeEventListener(SESSION_UPDATED_EVENT, handleSessionUpdate as EventListener);
    };
  }, []);

  useEffect(() => {
    function handleStorage(event: StorageEvent) {
      if (event.key !== SESSION_STORAGE_KEY) return;

      const stored = parseStoredSession(event.newValue);

      if (!stored) {
        resetSession(accessTokenRef.current, { persist: false });
        return;
      }

      commitSession(stored.tokens, stored.currentUser, { persist: false });
    }

    function handleFocus() {
      syncFromStoredSession();
    }

    function handleVisibilityChange() {
      if (document.visibilityState === "visible") {
        syncFromStoredSession();
      }
    }

    window.addEventListener("storage", handleStorage);
    window.addEventListener("focus", handleFocus);
    document.addEventListener("visibilitychange", handleVisibilityChange);

    return () => {
      window.removeEventListener("storage", handleStorage);
      window.removeEventListener("focus", handleFocus);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
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
  }, []);

  return (
    <SessionContext.Provider
      value={{
        status,
        tokens,
        currentUser,
        signIn,
        signUp,
        rotate,
        signOut,
      }}
    >
      {children}
      {sessionExpired ? (
        <div
          className="fixed inset-0 z-[100] flex items-end justify-center p-4 sm:items-center"
          style={{ background: "rgba(0,0,0,0.7)" }}
        >
          <div
            className="w-full max-w-lg rounded-[28px] border p-6 shadow-[0_24px_80px_rgba(0,0,0,0.55)]"
            style={{ background: "var(--panel)", borderColor: "var(--border-strong)", color: "var(--text)" }}
          >
            <div className="text-xs font-black uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>
              Authentication Required
            </div>
            <h2 className="mt-2 text-2xl font-bold">{sessionExpired.title}</h2>
            <p className="mt-3 text-sm leading-6" style={{ color: "var(--text-soft)" }}>
              {sessionExpired.message}
            </p>

            <div
              className="mt-4 rounded-2xl border px-4 py-3 text-sm"
              style={{ background: "var(--panel-muted)", borderColor: "var(--border-strong)", color: "var(--text-soft)" }}
            >
              {sessionExpired.instructions.map((instruction) => (
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
                Open Login In New Tab
              </button>
              <button
                type="button"
                onClick={() => setSessionExpired(null)}
                className="flex-1 rounded-2xl border px-4 py-3 text-sm font-semibold"
                style={{ borderColor: "var(--border-strong)", color: "var(--text-soft)" }}
              >
                Dismiss
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </SessionContext.Provider>
  );
}

export function useSession() {
  const context = useContext(SessionContext);

  if (!context) {
    throw new Error("useSession must be used within SessionProvider");
  }

  return context;
}

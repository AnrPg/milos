"use client";




import {useUiTranslations} from "@/i18n/ui";
import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { reportMyTimeZone } from "@/api/profile";
import { deviceTimeZone } from "@/lib/zoned-time";

import {
  acceptInvitation as acceptInvitationRequest,
  fetchCurrentUser,
  loginUser,
  logoutSession,
  refreshSession,
  registerAdminUser,
  registerInvitedUser,
  registerUser,
  type AcceptedInvitation,
  type AdminRegisterRequest,
  type AuthTokens,
  type CurrentUser,
  type LoginRequest,
  type InvitedRegisterRequest,
  type RegisterRequest,
} from "@/api/auth";
import {
  broadcastSessionSignOut,
  SELECTED_ORGANIZATION_SLUG_KEY,
  SESSION_EXPIRED_EVENT,
  SESSION_UPDATED_EVENT,
  setApiSessionUser,
} from "@/api/client";
import {
  clearWorkoutCache,
  clearBrowserPushSubscription,
  setWorkoutCacheUser,
} from "@/lib/push-subscription";
import { endLoginSession, startLoginSession } from "@/lib/login-session";
import { resetRealtimeSocket } from "@/lib/realtime";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { isAppLocale, persistLocaleCookie, type AppLocale } from "@/i18n/locales";
import { Dialog } from "@/components/ui/Dialog";

type SessionStatus = "loading" | "guest" | "authenticated";

type SessionContextValue = {
  status: SessionStatus;
  tokens: AuthTokens | null;
  currentUser: CurrentUser | null;
  signIn: (payload: LoginRequest) => Promise<CurrentUser>;
  signUp: (payload: RegisterRequest) => Promise<CurrentUser>;
  signUpAdmin: (payload: AdminRegisterRequest) => Promise<CurrentUser>;
  signUpInvited: (payload: InvitedRegisterRequest) => Promise<CurrentUser>;
  /** ADR-204: the signed-in profile accepts an invitation, keeping the session alive if its role changes. */
  acceptInvitation: (invitationToken: string) => Promise<AcceptedInvitation>;
  rotate: () => Promise<void>;
  /** ADR-187: takes over a session issued for another profile of the same login. */
  switchSession: (issuedTokens: AuthTokens) => Promise<CurrentUser>;
  signOut: () => void;
};

type SessionExpiredState = {
  title: string;
  message: string;
  instructions: string[];
} | null;

const SessionContext = createContext<SessionContextValue | null>(null);

// ADR-178: login and refresh return the user with the tokens, so opening the
// app needs no separate /auth/me round trip; registration still fetches it.
function sessionUser(tokens: AuthTokens): Promise<CurrentUser> {
  return tokens.user ? Promise.resolve(tokens.user) : fetchCurrentUser(tokens.access_token);
}

// ADR-195: a new account keeps the language its sign-up page was shown in
// (the signed-out language picker or the browser's), instead of opening in
// English and switching back on its first signed-in screen.
function withPageLocale<T extends { preferred_locale?: AppLocale }>(payload: T): T {
  if (payload.preferred_locale || typeof document === "undefined") return payload;
  const pageLocale = document.documentElement.lang;
  return isAppLocale(pageLocale) ? { ...payload, preferred_locale: pageLocale } : payload;
}

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

  // ADR-179: the API learns which zone this device is in (the latest device
  // wins), so pushes can add the reader's own time beside the organiser's.
  const storedTimeZone = (currentUser as { time_zone?: string | null } | null)?.time_zone ?? null;
  const reportedTimeZone = useRef<string | null>(null);
  const signedInUserId = currentUser?.id ?? null;
  useEffect(() => {
    const token = tokens?.access_token;
    const zone = deviceTimeZone();
    if (status !== "authenticated" || !token || !signedInUserId || !zone) return;
    if (zone === storedTimeZone || reportedTimeZone.current === `${signedInUserId}:${zone}`) return;
    reportedTimeZone.current = `${signedInUserId}:${zone}`;
    void reportMyTimeZone(token, zone).catch(() => undefined);
  }, [signedInUserId, status, storedTimeZone, tokens?.access_token]);

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
    endLoginSession();
    resetRealtimeSocket();
    void setWorkoutCacheUser(null);
    try {
      window.localStorage.removeItem(SELECTED_ORGANIZATION_SLUG_KEY);
    } catch {}
    setTokens(null);
    setCurrentUser(null);
    setStatus("guest");
    setApiSessionUser(null);

    void clearBrowserPushSubscription(accessTokenForCleanup);
  }

  async function establishSession(issuedTokens: AuthTokens) {
    const user = await sessionUser(issuedTokens);
    // A fresh sign-in (not a restore): "until next login" UI shows again.
    startLoginSession();
    commitSession(issuedTokens, user);
    return user;
  }

  async function signIn(payload: LoginRequest) {
    const issuedTokens = await loginUser(payload);
    return establishSession(issuedTokens);
  }

  async function signUp(payload: RegisterRequest) {
    const issuedTokens = await registerUser(withPageLocale(payload));
    return establishSession(issuedTokens);
  }

  async function signUpAdmin(payload: AdminRegisterRequest) {
    const issuedTokens = await registerAdminUser(withPageLocale(payload));
    return establishSession(issuedTokens);
  }

  async function signUpInvited(payload: InvitedRegisterRequest) {
    const issuedTokens = await registerInvitedUser(withPageLocale(payload));
    return establishSession(issuedTokens);
  }

  async function acceptInvitation(invitationToken: string) {
    if (!tokens) throw new Error(tSession("expiredMessage"));
    const accepted = await acceptInvitationRequest(tokens.access_token, invitationToken);
    if (accepted.access_token && accepted.user) {
      commitSession({ access_token: accepted.access_token, user: accepted.user }, accepted.user);
    }
    return accepted;
  }

  // Another profile is another person to the app: drop what belonged to the
  // previous one (live socket, chosen gym) before committing the new session.
  async function switchSession(issuedTokens: AuthTokens) {
    resetRealtimeSocket();
    try {
      window.localStorage.removeItem(SELECTED_ORGANIZATION_SLUG_KEY);
    } catch {}
    return establishSession(issuedTokens);
  }

  async function rotate() {
    if (!tokens) return;

    const refreshedTokens = await refreshSession();
    if (!refreshedTokens?.access_token) {
      resetSession(tokens.access_token);
      return;
    }
    const user = refreshedTokens.user ?? currentUser ?? (await fetchCurrentUser(refreshedTokens.access_token));
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
        const user = await sessionUser(refreshedTokens);
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
          customEvent.detail.currentUser ?? (await sessionUser(customEvent.detail.tokens));
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
        signUpInvited,
        acceptInvitation,
        rotate,
        switchSession,
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

  return (
    <Dialog
      onClose={onDismiss}
      layer="toast"
      eyebrow={requiredLabel}
      title={state.title}
      titleId="session-expired-title"
      closeLabel={dismissLabel}
      size="lg"
      footer={
        <div className="w-full flex flex-col gap-3 sm:flex-row">
              <button
                type="button"
                onClick={() => window.open("/login", "_blank", "noopener,noreferrer")}
                className="flex-1 rounded-2xl px-4 py-3 text-sm font-bold"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
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
      }
    >
            <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
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
    </Dialog>
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

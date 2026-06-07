"use client";

import { createContext, useContext, useEffect, useState } from "react";

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
import { ApiError } from "@/api/client";
import { clearStoredSession, readStoredSession, writeStoredSession } from "@/lib/session-storage";

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

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [status, setStatus] = useState<SessionStatus>("loading");
  const [tokens, setTokens] = useState<AuthTokens | null>(null);
  const [currentUser, setCurrentUser] = useState<CurrentUser | null>(null);

  function commitSession(nextTokens: AuthTokens, user: CurrentUser) {
    setTokens(nextTokens);
    setCurrentUser(user);
    setStatus("authenticated");
    writeStoredSession({ tokens: nextTokens, currentUser: user });
  }

  function resetSession() {
    setTokens(null);
    setCurrentUser(null);
    setStatus("guest");
    clearStoredSession();
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
    resetSession();
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
          if (!cancelled) resetSession();
        }
      }
    }

    void bootstrap();

    return () => {
      cancelled = true;
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

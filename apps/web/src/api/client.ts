import { clearStoredSession, readStoredSession, writeStoredSession } from "@/lib/session-storage";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "/api";
export const SESSION_UPDATED_EVENT = "milos:session-updated";
export const SESSION_EXPIRED_EVENT = "milos:session-expired";

type SessionTokens = {
  access_token: string;
  refresh_token: string;
};

type SessionSnapshot = {
  tokens: SessionTokens | null;
  currentUser: unknown | null;
};

type SessionExpiredDetail = {
  reason: "missing_refresh_token" | "refresh_failed";
};

export type ApiErrorPayload = {
  error?: string;
  errors?: Record<string, unknown>;
};

export class ApiError extends Error {
  status: number;
  payload: ApiErrorPayload;

  constructor(status: number, message: string, payload: ApiErrorPayload) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.payload = payload;
  }
}

type ApiRequestOptions = {
  method?: "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
  token?: string | null;
  body?: unknown;
};

let refreshPromise: Promise<string | null> | null = null;

function broadcastSessionUpdate(snapshot: SessionSnapshot) {
  if (typeof window === "undefined") return;

  window.dispatchEvent(
    new CustomEvent<SessionSnapshot>(SESSION_UPDATED_EVENT, {
      detail: snapshot,
    }),
  );
}

function broadcastSessionExpired(detail: SessionExpiredDetail) {
  if (typeof window === "undefined") return;

  window.dispatchEvent(
    new CustomEvent<SessionExpiredDetail>(SESSION_EXPIRED_EVENT, {
      detail,
    }),
  );
}

async function refreshAccessToken(): Promise<string | null> {
  if (refreshPromise) return refreshPromise;

  refreshPromise = (async () => {
    const stored = readStoredSession();

    if (!stored?.tokens.refresh_token) {
      clearStoredSession();
      broadcastSessionExpired({ reason: "missing_refresh_token" });
      broadcastSessionUpdate({ tokens: null, currentUser: null });
      return null;
    }

    const attemptedRefreshToken = stored.tokens.refresh_token;

    const response = await fetch(`${API_BASE_URL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: attemptedRefreshToken }),
    });

    if (!response.ok) {
      const latest = readStoredSession();

      if (latest?.tokens.refresh_token && latest.tokens.refresh_token !== attemptedRefreshToken) {
        broadcastSessionUpdate({
          tokens: latest.tokens,
          currentUser: latest.currentUser,
        });

        return latest.tokens.access_token;
      }

      clearStoredSession();
      broadcastSessionExpired({ reason: "refresh_failed" });
      broadcastSessionUpdate({ tokens: null, currentUser: null });
      return null;
    }

    const refreshedTokens = (await response.json()) as SessionTokens;

    writeStoredSession({
      tokens: refreshedTokens,
      currentUser: stored.currentUser,
    });

    broadcastSessionUpdate({
      tokens: refreshedTokens,
      currentUser: stored.currentUser,
    });

    return refreshedTokens.access_token;
  })();

  try {
    return await refreshPromise;
  } finally {
    refreshPromise = null;
  }
}

export async function apiRequest<T>(
  path: string,
  options: ApiRequestOptions = {},
  allowRefresh = true,
): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: options.method ?? "GET",
    headers: {
      "Content-Type": "application/json",
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (response.status === 401 && allowRefresh && options.token) {
    const refreshedToken = await refreshAccessToken();

    if (refreshedToken) {
      return apiRequest<T>(
        path,
        {
          ...options,
          token: refreshedToken,
        },
        false,
      );
    }
  }

  const payload = (await response.json().catch(() => ({}))) as T | ApiErrorPayload;

  if (!response.ok) {
    const message =
      typeof payload === "object" && payload !== null && "error" in payload && typeof payload.error === "string"
        ? payload.error
        : typeof payload === "object" &&
            payload !== null &&
            "errors" in payload &&
            payload.errors &&
            Object.keys(payload.errors).length > 0
          ? formatFieldErrors(payload.errors)
        : `Request failed with status ${response.status}`;

    throw new ApiError(response.status, message, (payload as ApiErrorPayload) ?? {});
  }

  return payload as T;
}

function formatFieldErrors(errors: Record<string, unknown>) {
  const messages = flattenFieldErrors(errors);

  if (messages.length === 0) {
    return "Validation failed";
  }

  return messages.join(" | ");
}

function flattenFieldErrors(errors: unknown, path = ""): string[] {
  if (Array.isArray(errors)) {
    return errors.map((message) => formatErrorMessage(path, message));
  }

  if (typeof errors === "string") {
    return [formatErrorMessage(path, errors)];
  }

  if (errors && typeof errors === "object") {
    return Object.entries(errors as Record<string, unknown>).flatMap(([field, value]) => {
      const nextPath = path ? `${path}.${field}` : field;
      return flattenFieldErrors(value, nextPath);
    });
  }

  if (errors == null) {
    return [];
  }

  return [formatErrorMessage(path, String(errors))];
}

function formatErrorMessage(path: string, message: unknown) {
  const text = typeof message === "string" ? message : JSON.stringify(message);
  return path ? `${path}: ${text}` : text;
}

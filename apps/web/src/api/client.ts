const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "/api";
export const SESSION_UPDATED_EVENT = "milos:session-updated";
export const SESSION_EXPIRED_EVENT = "milos:session-expired";

type SessionTokens = {
  access_token: string;
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
  future_class_count?: number;
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
let sessionUser: unknown | null = null;
let latestSharedAccessToken: string | null = null;
let sessionChannel: BroadcastChannel | null = null;

function getSessionChannel() {
  if (typeof window === "undefined" || !("BroadcastChannel" in window)) return null;
  if (sessionChannel) return sessionChannel;

  sessionChannel = new BroadcastChannel("milos-session-v1");
  sessionChannel.addEventListener("message", (event: MessageEvent<{ access_token?: string; signed_out?: boolean }>) => {
    if (event.data?.signed_out) {
      latestSharedAccessToken = null;
      broadcastSessionUpdate({ tokens: null, currentUser: null });
      return;
    }
    const accessToken = event.data?.access_token;
    if (!accessToken) return;
    latestSharedAccessToken = accessToken;
    broadcastSessionUpdate({ tokens: { access_token: accessToken }, currentUser: sessionUser });
  });
  return sessionChannel;
}

export function broadcastSessionSignOut() {
  latestSharedAccessToken = null;
  getSessionChannel()?.postMessage({ signed_out: true });
}

export function setApiSessionUser(user: unknown | null) {
  sessionUser = user;
}

function tokenExpiresSoon(token: string, leewaySeconds = 30): boolean {
  const [, payload] = token.split(".");
  if (!payload || typeof window === "undefined") return false;

  try {
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
    const claims = JSON.parse(window.atob(padded)) as { exp?: unknown };

    return typeof claims.exp === "number" && claims.exp <= Math.floor(Date.now() / 1000) + leewaySeconds;
  } catch {
    return false;
  }
}

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

  const performRefresh = async () => {
    if (latestSharedAccessToken && !tokenExpiresSoon(latestSharedAccessToken, 60)) {
      return latestSharedAccessToken;
    }

    const response = await fetch(`${API_BASE_URL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "same-origin",
    });

    if (!response.ok) {
      broadcastSessionExpired({ reason: "refresh_failed" });
      broadcastSessionUpdate({ tokens: null, currentUser: null });
      return null;
    }

    const refreshedTokens = (await response.json()) as SessionTokens;
    latestSharedAccessToken = refreshedTokens.access_token;
    getSessionChannel()?.postMessage(refreshedTokens);

    broadcastSessionUpdate({
      tokens: refreshedTokens,
      currentUser: sessionUser,
    });

    return refreshedTokens.access_token;
  };

  refreshPromise = (async () => {
    if (typeof navigator !== "undefined" && navigator.locks) {
      return await navigator.locks.request("milos-refresh-cookie", async () => {
        return await performRefresh();
      });
    }

    return await performRefresh();
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
  getSessionChannel();
  const token =
    allowRefresh && options.token && tokenExpiresSoon(options.token)
      ? (await refreshAccessToken()) ?? options.token
      : options.token;

  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: options.method ?? "GET",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
    credentials: "same-origin",
  });

  if (response.status === 401 && allowRefresh && token) {
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

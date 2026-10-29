const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "/api";
export const SELECTED_ORGANIZATION_SLUG_KEY = "palee:selected-organization-slug";
export const SESSION_UPDATED_EVENT = "palee:session-updated";
export const SESSION_EXPIRED_EVENT = "palee:session-expired";
/**
 * ADR-184: a business in demo mode tried to go live (403
 * `business_not_activated`). The demo-mode host shows one friendly notice.
 */
export const BUSINESS_NOT_ACTIVATED_EVENT = "palee:business-not-activated";
export const BUSINESS_NOT_ACTIVATED_CODE = "business_not_activated";

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
  code?: string;
  params?: Record<string, unknown>;
  error?: string;
  errors?: Record<string, unknown>;
  /** Extra structured detail for some codes (e.g. ADR-180 `invalid_text_sections`). */
  details?: Record<string, unknown>;
  diagnostics?: Array<{
    code: string;
    severity: "error" | "warning";
    line: number;
    column: number;
    params: Record<string, unknown>;
  }>;
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
  /**
   * "text" returns the raw body of a successful response (e.g. a printable HTML document);
   * "blob" returns it as a Blob (a PDF, a ZIP or an export file to save).
   */
  responseType?: "json" | "text" | "blob";
  /** Cancels the request (react-query passes one so stale searches stop). */
  signal?: AbortSignal;
  /**
   * `"account"` sends the path as is, never under `/org/:slug`: the account
   * read model (ADR-162) shares paths such as `/me/history` and
   * `/me/progress` with their older per-gym versions.
   */
  scope?: "tenant" | "account";
  /** Extra request headers (ADR-208: the sign-in device id). */
  headers?: Record<string, string>;
};

function organizationSlugFromPath() {
  if (typeof window === "undefined") return null;
  return window.location.pathname.match(/^\/org\/([^/]+)/)?.[1] ?? null;
}

function selectedOrganizationSlug() {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY);
  } catch {
    return null;
  }
}

function organizationSlugFromToken(token?: string | null) {
  if (!token || typeof window === "undefined") return null;

  try {
    const payload = token.split(".")[1];
    if (!payload) return null;
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
    const claims = JSON.parse(window.atob(padded)) as {
      memberships?: Array<{ organization_slug?: unknown }>;
    };
    const slug = claims.memberships?.[0]?.organization_slug;
    return typeof slug === "string" && slug.length > 0 ? slug : null;
  } catch {
    return null;
  }
}

function organizationSlugForRequest(token?: string | null) {
  return organizationSlugFromPath() ?? selectedOrganizationSlug() ?? organizationSlugFromToken(token);
}

/** The organization a tenant-scoped request would target right now. */
export function currentOrganizationSlug(token?: string | null) {
  return organizationSlugForRequest(token);
}

const TENANT_SCOPED_PREFIXES = [
  "/admin",
  "/anatomy/nodes",
  "/bookings",
  "/challenges",
  "/class-timers",
  "/check-ins",
  "/landing",
  "/locations",
  "/me/appointments",
  "/me/corporate-enrollment",
  "/me/entitlement",
  "/me/finance",
  "/me/form-reviews",
  "/me/goal-feedback",
  "/me/history",
  "/me/home-location",
  "/me/roles",
  "/me/invoices",
  "/me/refund-receipts",
  "/me/nutrition-plan",
  "/me/progress",
  "/me/reviews",
  "/me/search/users",
  "/me/seasons",
  "/me/threads",
  "/me/training-log",
  "/me/workouts",
  "/my-workouts",
  "/schedule",
  "/staff",
  "/me/videos",
];

function pathMatchesPrefix(path: string, prefix: string) {
  return path === prefix || path.startsWith(`${prefix}/`) || path.startsWith(`${prefix}?`);
}

function isMemberWorkoutPath(path: string) {
  if (!pathMatchesPrefix(path, "/workouts")) return false;
  return !/^\/workouts\/[^/?]+\/timer-sequence(?:\?|$)/.test(path);
}

function isTenantScopedRequest(path: string) {
  return (
    TENANT_SCOPED_PREFIXES.some((prefix) => pathMatchesPrefix(path, prefix)) ||
    isMemberWorkoutPath(path)
  );
}

function tenantScopedPath(path: string, organizationSlug: string | null) {
  if (!organizationSlug) return path;
  if (path === "/org" || path.startsWith("/org/")) return path;

  if (!isTenantScopedRequest(path)) return path;

  return `/org/${organizationSlug}${path}`;
}

function rememberOrganizationSlug(slug: string) {
  if (typeof window === "undefined") return;

  try {
    window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, slug);
  } catch {}
}

// ADR-122: the API resolves a retired organization slug transparently and
// names the current one in this header. A remembered selection that still
// holds the retired slug is updated so later requests use the new one.
export const CANONICAL_ORGANIZATION_SLUG_HEADER = "x-organization-canonical-slug";

function rememberCanonicalOrganizationSlug(response: Response, requestedSlug: string | null) {
  const canonicalSlug = response.headers?.get?.(CANONICAL_ORGANIZATION_SLUG_HEADER);
  if (!canonicalSlug || !requestedSlug || canonicalSlug === requestedSlug) return;
  if (selectedOrganizationSlug() === requestedSlug) rememberOrganizationSlug(canonicalSlug);
}

let refreshPromise: Promise<string | null> | null = null;
let sessionUser: unknown | null = null;
let latestSharedAccessToken: string | null = null;
let sessionChannel: BroadcastChannel | null = null;
let membershipSlugPromise: Promise<string | null> | null = null;

async function fetchMembershipOrganizationSlug(token: string) {
  const response = await fetch(`${API_BASE_URL}/memberships`, {
    method: "GET",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    credentials: "same-origin",
  });

  if (!response.ok) return null;

  const memberships = (await response.json().catch(() => [])) as Array<{
    organization?: { slug?: unknown };
    role?: unknown;
  }>;
  const adminMembership =
    memberships.find((membership) =>
      ["owner", "admin", "coach"].includes(String(membership.role)),
    ) ?? memberships[0];
  const slug = adminMembership?.organization?.slug;

  if (typeof slug !== "string" || slug.length === 0) return null;

  rememberOrganizationSlug(slug);
  return slug;
}

async function resolveOrganizationSlugForRequest(path: string, token?: string | null) {
  const knownSlug = organizationSlugForRequest(token);

  if (knownSlug || !token || !isTenantScopedRequest(path)) {
    return knownSlug;
  }

  membershipSlugPromise ??= fetchMembershipOrganizationSlug(token);

  try {
    return await membershipSlugPromise;
  } finally {
    membershipSlugPromise = null;
  }
}

function getSessionChannel() {
  if (typeof window === "undefined" || !("BroadcastChannel" in window)) return null;
  if (sessionChannel) return sessionChannel;

  sessionChannel = new BroadcastChannel("palee-session-v1");
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
      return await navigator.locks.request("palee-refresh-cookie", async () => {
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
  const organizationSlug =
    options.scope === "account" ? null : await resolveOrganizationSlugForRequest(path, token);
  const requestPath = tenantScopedPath(path, organizationSlug);

  const response = await fetch(`${API_BASE_URL}${requestPath}`, {
    method: options.method ?? "GET",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(organizationSlug ? { "X-Organization-Slug": organizationSlug } : {}),
      ...options.headers,
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
    credentials: "same-origin",
    signal: options.signal,
  });

  rememberCanonicalOrganizationSlug(response, organizationSlug);

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

  if (options.responseType === "text" && response.ok) {
    return (await response.text()) as T;
  }

  if (options.responseType === "blob" && response.ok) {
    return (await response.blob()) as T;
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

    const errorPayload = (payload as ApiErrorPayload) ?? {};
    if (errorPayload.code === BUSINESS_NOT_ACTIVATED_CODE && typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent(BUSINESS_NOT_ACTIVATED_EVENT));
    }
    throw new ApiError(response.status, message, errorPayload);
  }

  if (response.status === 204) {
    return undefined as T;
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

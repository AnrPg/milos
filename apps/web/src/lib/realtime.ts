"use client";

import { Socket, type Channel } from "phoenix";

import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";

let activeSocket: Socket | null = null;
let activeToken: string | null = null;
let activeOrganizationSlug: string | null = null;

type LifecycleHandlers = {
  onJoin?: () => void;
  onJoinError?: (payload: unknown) => void;
  onDisconnect?: () => void;
  onChannelError?: () => void;
};

function socketEndpoint() {
  const explicit = process.env.NEXT_PUBLIC_API_WS_URL;

  if (explicit) return explicit;
  if (typeof window === "undefined") return "ws://localhost:4000/socket";

  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}/socket`;
}

type MembershipClaim = {
  organization_id: string;
  organization_slug: string;
};

function membershipClaims(token: string): MembershipClaim[] {
  try {
    const payload = token.split(".")[1];
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
    const claims = JSON.parse(window.atob(padded)) as { memberships?: MembershipClaim[] };
    return claims.memberships ?? [];
  } catch {
    return [];
  }
}

function organizationSlug(token: string) {
  const pathSlug =
    typeof window === "undefined"
      ? null
      : window.location.pathname.match(/^\/org\/([^/]+)/)?.[1] ?? null;

  return pathSlug ?? selectedOrganizationSlug() ?? membershipClaims(token)[0]?.organization_slug ?? null;
}

function selectedOrganizationSlug() {
  if (typeof window === "undefined") return null;

  try {
    const slug = window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY);
    return slug && slug.length > 0 ? slug : null;
  } catch {
    return null;
  }
}

export function organizationTopic(token: string, suffix: string) {
  const slug = organizationSlug(token);
  const membership = membershipClaims(token).find((entry) => entry.organization_slug === slug);
  if (!membership) return null;
  if (suffix === "schedule") return `schedule:${membership.organization_id}`;
  if (suffix.startsWith("chat:thread:")) {
    return `chat:${membership.organization_id}:thread:${suffix.slice("chat:thread:".length)}`;
  }

  return `org:${membership.organization_id}:${suffix}`;
}

function ensureSocket(token: string) {
  const nextOrganizationSlug = organizationSlug(token);

  if (
    activeSocket &&
    activeToken === token &&
    activeOrganizationSlug === nextOrganizationSlug
  ) {
    return activeSocket;
  }

  if (activeSocket) {
    activeSocket.disconnect();
  }

  activeToken = token;
  activeOrganizationSlug = nextOrganizationSlug;
  activeSocket = new Socket(socketEndpoint(), {
    params: { token, organization_slug: nextOrganizationSlug },
  });
  activeSocket.connect();
  return activeSocket;
}

export function resetRealtimeSocket() {
  if (activeSocket) {
    activeSocket.disconnect();
  }

  activeSocket = null;
  activeToken = null;
  activeOrganizationSlug = null;
}

export function joinChannelWithPush(
  token: string,
  topic: string,
  handlers: Record<string, (payload: unknown) => void>,
): {
  push: <T>(event: string, payload: Record<string, unknown>) => Promise<T>;
  leave: () => void;
} {
  const socket = ensureSocket(token);
  const channel = socket.channel(topic, {});

  Object.entries(handlers).forEach(([event, handler]) => {
    channel.on(event, (payload) => {
      handler(payload);
    });
  });

  channel.join();

  return {
    push: <T>(event: string, payload: Record<string, unknown>) =>
      new Promise<T>((resolve, reject) => {
        channel
          .push(event, payload)
          .receive("ok", (response) => resolve(response as T))
          .receive("error", (response) => reject(new ChannelPushError(event, response)))
          .receive("timeout", () => reject(new ChannelPushError(event, { reason: "timeout" })));
      }),
    leave: () => {
      channel.leave();
    },
  };
}

export class ChannelPushError extends Error {
  readonly event: string;
  readonly response: unknown;

  constructor(event: string, response: unknown) {
    const reason =
      typeof response === "object" && response !== null && "reason" in response
        ? String(response.reason)
        : "realtime command failed";

    super(reason);
    this.name = "ChannelPushError";
    this.event = event;
    this.response = response;
  }
}

export function subscribeToTopic(
  token: string,
  topic: string,
  handlers: Record<string, (payload: unknown) => void>,
  lifecycle: LifecycleHandlers = {},
) {
  const socket = ensureSocket(token);
  const channel: Channel = socket.channel(topic, {});

  Object.entries(handlers).forEach(([event, handler]) => {
    channel.on(event, (payload) => {
      handler(payload);
    });
  });

  channel.on("phx_error", () => {
    lifecycle.onChannelError?.();
  });

  channel.on("phx_close", () => {
    lifecycle.onDisconnect?.();
  });

  channel
    .join()
    .receive("ok", () => {
      lifecycle.onJoin?.();
    })
    .receive("error", (payload) => {
      lifecycle.onJoinError?.(payload);
    });

  return () => {
    channel.leave();
  };
}

"use client";

import { Socket, type Channel } from "phoenix";
import { useSyncExternalStore } from "react";

import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";

type LifecycleHandlers = {
  onJoin?: () => void;
  /** A join after the first (the socket came back): events may have been missed, so resync. */
  onRejoin?: () => void;
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

function topicNeedsTenantContext(topic: string) {
  return (
    topic.startsWith("schedule:") ||
    topic.startsWith("chat:") ||
    topic.startsWith("org:") ||
    topic.startsWith("class_timer:")
  );
}

type Handler = (payload: unknown) => void;

type Listener = {
  handlers: Record<string, Handler>;
  lifecycle: LifecycleHandlers;
  joins: number;
};

type TopicEntry = {
  channel: Channel;
  listeners: Set<Listener>;
  events: Set<string>;
  joined: boolean;
};

type SocketRecord = {
  socket: Socket;
  topics: Map<string, TopicEntry>;
};

/**
 * One socket for the person (user-wide topics) and one per gym for tenant
 * topics, each opened once and kept: a token renewal or a page that mixes
 * both kinds of topic no longer drops the connection. Every topic has one
 * channel, shared by every subscriber (the server closes the older of two
 * joins to the same topic). Reconnects read the latest token.
 */
const USER_SOCKET = "";
const sockets = new Map<string, SocketRecord>();
let latestToken: string | null = null;

let connected = false;
const statusListeners = new Set<() => void>();

function setConnected(next: boolean) {
  if (connected === next) return;
  connected = next;
  statusListeners.forEach((listener) => listener());
}

/** Whether the person's live connection is up (live events arrive). */
export function realtimeConnected() {
  return connected;
}

export function onRealtimeStatusChange(listener: () => void) {
  statusListeners.add(listener);
  return () => {
    statusListeners.delete(listener);
  };
}

export function useRealtimeConnected() {
  return useSyncExternalStore(onRealtimeStatusChange, realtimeConnected, () => false);
}

/**
 * A polling interval for data that live events keep current: none while the
 * connection is up, `ms` while it is down, so nothing goes stale unnoticed.
 */
export function useRealtimeFallbackInterval(ms: number): number | false {
  return useRealtimeConnected() ? false : ms;
}

function socketKey(token: string, topic: string) {
  return topicNeedsTenantContext(topic) ? (organizationSlug(token) ?? USER_SOCKET) : USER_SOCKET;
}

function ensureSocket(key: string) {
  const existing = sockets.get(key);
  if (existing) return existing;

  const socket = new Socket(socketEndpoint(), {
    params: () => (key === USER_SOCKET ? { token: latestToken } : { token: latestToken, organization_slug: key }),
  });
  if (key === USER_SOCKET) {
    socket.onOpen(() => setConnected(true));
    socket.onClose(() => setConnected(false));
    socket.onError(() => setConnected(false));
  }
  const record: SocketRecord = { socket, topics: new Map() };
  sockets.set(key, record);
  socket.connect();
  return record;
}

export function resetRealtimeSocket() {
  sockets.forEach((record) => record.socket.disconnect());
  sockets.clear();
  latestToken = null;
  setConnected(false);
}

function openTopic(record: SocketRecord, topic: string) {
  const channel = record.socket.channel(topic, {});
  const entry: TopicEntry = { channel, listeners: new Set(), events: new Set(), joined: false };

  channel.on("phx_error", () => {
    entry.joined = false;
    entry.listeners.forEach((listener) => listener.lifecycle.onChannelError?.());
  });
  channel.on("phx_close", () => {
    entry.joined = false;
    // Closed by the server: the next subscriber opens a fresh channel.
    if (record.topics.get(topic) === entry) record.topics.delete(topic);
    entry.listeners.forEach((listener) => listener.lifecycle.onDisconnect?.());
  });
  channel
    .join()
    .receive("ok", () => {
      entry.joined = true;
      entry.listeners.forEach((listener) => announceJoin(listener));
    })
    .receive("error", (payload) => {
      entry.listeners.forEach((listener) => listener.lifecycle.onJoinError?.(payload));
    });

  record.topics.set(topic, entry);
  return entry;
}

function announceJoin(listener: Listener) {
  listener.joins += 1;
  listener.lifecycle.onJoin?.();
  if (listener.joins > 1) listener.lifecycle.onRejoin?.();
}

function listen(token: string, topic: string, handlers: Record<string, Handler>, lifecycle: LifecycleHandlers) {
  latestToken = token;
  const key = socketKey(token, topic);
  const record = ensureSocket(key);
  const entry = record.topics.get(topic) ?? openTopic(record, topic);
  const listener: Listener = { handlers, lifecycle, joins: 0 };

  Object.keys(handlers).forEach((event) => {
    if (entry.events.has(event)) return;
    entry.events.add(event);
    entry.channel.on(event, (payload) => {
      entry.listeners.forEach((current) => current.handlers[event]?.(payload));
    });
  });

  entry.listeners.add(listener);
  if (entry.joined) announceJoin(listener);

  const stop = () => {
    if (!entry.listeners.delete(listener) || entry.listeners.size > 0) return;
    entry.channel.leave();
    if (record.topics.get(topic) === entry) record.topics.delete(topic);
    // A gym's socket closes with its last topic; the person's stays open.
    if (key !== USER_SOCKET && record.topics.size === 0 && sockets.get(key) === record) {
      record.socket.disconnect();
      sockets.delete(key);
    }
  };

  return { entry, stop };
}

export function joinChannelWithPush(
  token: string,
  topic: string,
  handlers: Record<string, Handler>,
): {
  push: <T>(event: string, payload: Record<string, unknown>) => Promise<T>;
  leave: () => void;
} {
  const { entry, stop } = listen(token, topic, handlers, {});

  return {
    push: <T>(event: string, payload: Record<string, unknown>) =>
      new Promise<T>((resolve, reject) => {
        entry.channel
          .push(event, payload)
          .receive("ok", (response) => resolve(response as T))
          .receive("error", (response) => reject(new ChannelPushError(event, response)))
          .receive("timeout", () => reject(new ChannelPushError(event, { reason: "timeout" })));
      }),
    leave: stop,
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
  handlers: Record<string, Handler>,
  lifecycle: LifecycleHandlers = {},
) {
  return listen(token, topic, handlers, lifecycle).stop;
}

"use client";

import { Socket, type Channel } from "phoenix";

let activeSocket: Socket | null = null;
let activeToken: string | null = null;

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

function ensureSocket(token: string) {
  if (activeSocket && activeToken === token) {
    return activeSocket;
  }

  if (activeSocket) {
    activeSocket.disconnect();
  }

  activeToken = token;
  activeSocket = new Socket(socketEndpoint(), { params: { token } });
  activeSocket.connect();
  return activeSocket;
}

export function resetRealtimeSocket() {
  if (activeSocket) {
    activeSocket.disconnect();
  }

  activeSocket = null;
  activeToken = null;
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

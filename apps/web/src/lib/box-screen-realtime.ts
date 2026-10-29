"use client";

import { Socket } from "phoenix";

// ADR-253: the TV's own socket, `/box_screen_socket`, which accepts only the
// display token (never a person's session, so it is separate from
// lib/realtime.ts). One socket per token; each topic has one channel.

function endpoint() {
  const explicit = process.env.NEXT_PUBLIC_API_WS_URL;
  if (explicit) return explicit.replace(/\/socket\/?$/, "/box_screen_socket");
  if (typeof window === "undefined") return "ws://localhost:4000/box_screen_socket";
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}/box_screen_socket`;
}

type Handlers = Record<string, (payload: unknown) => void>;
type Lifecycle = { onJoin?: () => void; onDown?: () => void };

let current: { token: string; socket: Socket } | null = null;
let users = 0;

function socketFor(token: string) {
  if (current?.token === token) return current.socket;
  current?.socket.disconnect();
  const socket = new Socket(endpoint(), { params: { token } });
  socket.connect();
  current = { token, socket };
  return socket;
}

/** Joins `topic` on the screen's socket; returns the leave function. */
export function subscribeScreenTopic(token: string, topic: string, handlers: Handlers, lifecycle: Lifecycle = {}) {
  const socket = socketFor(token);
  users += 1;
  const channel = socket.channel(topic, {});
  Object.entries(handlers).forEach(([event, handler]) => channel.on(event, handler));
  channel.onError(() => lifecycle.onDown?.());
  channel.onClose(() => lifecycle.onDown?.());
  channel
    .join()
    .receive("ok", () => lifecycle.onJoin?.())
    .receive("error", () => lifecycle.onDown?.());

  return () => {
    channel.leave();
    users -= 1;
    if (users === 0 && current?.socket === socket) {
      socket.disconnect();
      current = null;
    }
  };
}

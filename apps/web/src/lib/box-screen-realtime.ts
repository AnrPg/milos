"use client";

import { Socket } from "phoenix";

// ADR-253: the TV's own socket, `/box_screen_socket`, which accepts only the
// display token (never a person's session, so it is separate from
// lib/realtime.ts). One socket per token, closed with its last topic.

function endpoint() {
  const explicit = process.env.NEXT_PUBLIC_API_WS_URL;
  if (explicit) return explicit.replace(/\/socket\/?$/, "/box_screen_socket");
  if (typeof window === "undefined") return "ws://localhost:4000/box_screen_socket";
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}/box_screen_socket`;
}

type Handlers = Record<string, (payload: unknown) => void>;
type Lifecycle = { onJoin?: () => void; onDown?: () => void };

const sockets = new Map<string, { socket: Socket; users: number }>();

function socketFor(token: string) {
  let record = sockets.get(token);
  if (!record) {
    const socket = new Socket(endpoint(), { params: { token } });
    socket.connect();
    record = { socket, users: 0 };
    sockets.set(token, record);
  }
  record.users += 1;
  return record;
}

/** Joins `topic` on the screen's socket; returns the leave function. */
export function subscribeScreenTopic(token: string, topic: string, handlers: Handlers, lifecycle: Lifecycle = {}) {
  const record = socketFor(token);
  const channel = record.socket.channel(topic, {});
  Object.entries(handlers).forEach(([event, handler]) => channel.on(event, handler));
  channel.on("phx_error", () => lifecycle.onDown?.());
  channel.on("phx_close", () => lifecycle.onDown?.());
  channel
    .join()
    .receive("ok", () => lifecycle.onJoin?.())
    .receive("error", () => lifecycle.onDown?.());

  return () => {
    channel.leave();
    record.users -= 1;
    if (record.users === 0 && sockets.get(token) === record) {
      record.socket.disconnect();
      sockets.delete(token);
    }
  };
}

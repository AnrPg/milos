import { beforeEach, describe, expect, it, vi } from "vitest";

import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";

const phoenix = vi.hoisted(() => {
  type Receiver = (payload?: unknown) => void;
  const channels: MockChannel[] = [];
  const sockets: MockSocket[] = [];

  class MockChannel {
    handlers: Record<string, Receiver[]> = {};
    joinHooks: Record<string, Receiver> = {};
    receivers: Record<string, Receiver> = {};
    left = false;

    constructor(readonly topic: string) {}

    on(event: string, handler: Receiver) {
      (this.handlers[event] ??= []).push(handler);
    }

    emit(event: string, payload?: unknown) {
      (this.handlers[event] ?? []).forEach((handler) => handler(payload));
    }

    join() {
      const hooks = this.joinHooks;
      const result = {
        receive: (status: string, handler: Receiver) => {
          hooks[status] = handler;
          return result;
        },
      };
      return result;
    }

    receive(status: string, handler: Receiver) {
      this.receivers[status] = handler;
      return this;
    }

    push() {
      this.receivers = {};
      return {
        receive: (status: string, handler: Receiver) => {
          this.receivers[status] = handler;
          return this.pushResult();
        },
      };
    }

    pushResult() {
      return {
        receive: (status: string, handler: Receiver) => {
          this.receivers[status] = handler;
          return this.pushResult();
        },
      };
    }

    leave() {
      this.left = true;
    }
  }

  class MockSocket {
    connected = false;
    openCallbacks: Receiver[] = [];
    closeCallbacks: Receiver[] = [];

    constructor(
      readonly endpoint: string,
      readonly options: unknown,
    ) {
      sockets.push(this);
    }

    connect() {
      this.connected = true;
    }

    disconnect() {
      this.connected = false;
    }

    onOpen(callback: Receiver) {
      this.openCallbacks.push(callback);
    }

    onClose(callback: Receiver) {
      this.closeCallbacks.push(callback);
    }

    onError(callback: Receiver) {
      this.closeCallbacks.push(callback);
    }

    params() {
      return (this.options as { params: () => Record<string, unknown> }).params();
    }

    channel(topic: string) {
      const channel = new MockChannel(topic);
      channels.push(channel);
      return channel;
    }
  }

  return { Socket: MockSocket, channels, sockets };
});

vi.mock("phoenix", () => ({ Socket: phoenix.Socket }));

import {
  ChannelPushError,
  joinChannelWithPush,
  organizationTopic,
  realtimeConnected,
  resetRealtimeSocket,
  subscribeToTopic,
} from "@/lib/realtime";

describe("joinChannelWithPush", () => {
  beforeEach(() => {
    phoenix.channels.length = 0;
    phoenix.sockets.length = 0;
    resetRealtimeSocket();
    window.localStorage.clear();
    window.history.replaceState(null, "", "/");
  });

  it("resolves push replies when the channel acknowledges ok", async () => {
    const channel = joinChannelWithPush("token", "thread:1", {});
    const promise = channel.push<{ id: string }>("send_message", { body: "hello" });

    phoenix.channels[0].receivers.ok({ id: "message-1" });

    await expect(promise).resolves.toEqual({ id: "message-1" });
  });

  it("rejects push replies when the channel returns an error", async () => {
    const channel = joinChannelWithPush("token", "thread:1", {});
    const promise = channel.push("send_message", { body: "" });

    phoenix.channels[0].receivers.error({ reason: "unauthorized" });

    await expect(promise).rejects.toMatchObject({
      name: "ChannelPushError",
      event: "send_message",
      message: "unauthorized",
    });
  });

  it("rejects push replies when the channel times out", async () => {
    const channel = joinChannelWithPush("token", "thread:1", {});
    const promise = channel.push("typing_start", {});

    phoenix.channels[0].receivers.timeout();

    await expect(promise).rejects.toBeInstanceOf(ChannelPushError);
  });

  it("uses the selected organization for topics when the URL is not tenant-prefixed", () => {
    window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, "second-gym");
    const token = tokenWithMemberships([
      { organization_id: "org-1", organization_slug: "first-gym" },
      { organization_id: "org-2", organization_slug: "second-gym" },
    ]);

    expect(organizationTopic(token, "schedule")).toBe("schedule:org-2");
  });

  it("does not send stale tenant context for user-wide notification topics", () => {
    window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, "stale-gym");

    const unsubscribe = subscribeToTopic("token", "notifications:user-1", {});

    expect(phoenix.sockets[0].params()).toEqual({ token: "token" });

    unsubscribe();
  });
});

describe("subscribeToTopic", () => {
  const gymToken = tokenWithMemberships([{ organization_id: "org-1", organization_slug: "first-gym" }]);

  beforeEach(() => {
    phoenix.channels.length = 0;
    phoenix.sockets.length = 0;
    resetRealtimeSocket();
    window.localStorage.clear();
    window.history.replaceState(null, "", "/");
  });

  it("shares one channel between subscribers of the same topic", () => {
    const first = vi.fn();
    const second = vi.fn();
    const stopFirst = subscribeToTopic("token", "notifications:user-1", { "notifications:changed": first });
    const stopSecond = subscribeToTopic("token", "notifications:user-1", { "notifications:changed": second });

    expect(phoenix.channels).toHaveLength(1);
    phoenix.channels[0].emit("notifications:changed", { id: 1 });
    expect(first).toHaveBeenCalledWith({ id: 1 });
    expect(second).toHaveBeenCalledWith({ id: 1 });

    stopFirst();
    expect(phoenix.channels[0].left).toBe(false);
    phoenix.channels[0].emit("notifications:changed", { id: 2 });
    expect(first).toHaveBeenCalledTimes(1);
    expect(second).toHaveBeenCalledTimes(2);

    stopSecond();
    expect(phoenix.channels[0].left).toBe(true);
  });

  it("keeps user-wide and gym topics on their own sockets without reconnecting either", () => {
    window.localStorage.setItem(SELECTED_ORGANIZATION_SLUG_KEY, "first-gym");
    subscribeToTopic(gymToken, "notifications:user-1", {});
    const stopSchedule = subscribeToTopic(gymToken, "schedule:org-1", {});
    subscribeToTopic(gymToken, "sync:user-1", {});

    expect(phoenix.sockets).toHaveLength(2);
    expect(phoenix.sockets.every((socket) => socket.connected)).toBe(true);
    expect(phoenix.sockets[0].params()).toEqual({ token: gymToken });
    expect(phoenix.sockets[1].params()).toEqual({ token: gymToken, organization_slug: "first-gym" });

    // The gym's socket closes with its last topic; the person's stays.
    stopSchedule();
    expect(phoenix.sockets[1].connected).toBe(false);
    expect(phoenix.sockets[0].connected).toBe(true);
  });

  it("keeps the socket across a token renewal and reconnects with the newest token", () => {
    subscribeToTopic("old-token", "notifications:user-1", {});
    subscribeToTopic("new-token", "sync:user-1", {});

    expect(phoenix.sockets).toHaveLength(1);
    expect(phoenix.sockets[0].connected).toBe(true);
    expect(phoenix.sockets[0].params()).toEqual({ token: "new-token" });
  });

  it("reports the connection and asks subscribers to resync after a rejoin", () => {
    const onJoin = vi.fn();
    const onRejoin = vi.fn();
    subscribeToTopic("token", "notifications:user-1", {}, { onJoin, onRejoin });
    const socket = phoenix.sockets[0];

    socket.openCallbacks.forEach((callback) => callback());
    expect(realtimeConnected()).toBe(true);
    phoenix.channels[0].joinHooks.ok();
    expect(onJoin).toHaveBeenCalledTimes(1);
    expect(onRejoin).not.toHaveBeenCalled();

    socket.closeCallbacks.forEach((callback) => callback());
    expect(realtimeConnected()).toBe(false);
    socket.openCallbacks.forEach((callback) => callback());
    phoenix.channels[0].joinHooks.ok();
    expect(onRejoin).toHaveBeenCalledTimes(1);
  });

  it("tells a late subscriber the channel is already joined", () => {
    subscribeToTopic("token", "notifications:user-1", {});
    phoenix.channels[0].joinHooks.ok();
    const onJoin = vi.fn();
    subscribeToTopic("token", "notifications:user-1", {}, { onJoin });

    expect(onJoin).toHaveBeenCalledTimes(1);
  });
});

function tokenWithMemberships(memberships: Array<{ organization_id: string; organization_slug: string }>) {
  return `header.${window.btoa(JSON.stringify({ memberships }))}.signature`;
}

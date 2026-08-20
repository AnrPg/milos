import { beforeEach, describe, expect, it, vi } from "vitest";

import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";

const phoenix = vi.hoisted(() => {
  type Receiver = (payload?: unknown) => void;
  const channels: MockChannel[] = [];
  const sockets: MockSocket[] = [];

  class MockChannel {
    handlers: Record<string, Receiver> = {};
    receivers: Record<string, Receiver> = {};
    left = false;

    on(event: string, handler: Receiver) {
      this.handlers[event] = handler;
    }

    join() {
      return this;
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

    channel() {
      const channel = new MockChannel();
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

    expect(phoenix.sockets[0].options).toEqual({ params: { token: "token" } });

    unsubscribe();
  });
});

function tokenWithMemberships(memberships: Array<{ organization_id: string; organization_slug: string }>) {
  return `header.${window.btoa(JSON.stringify({ memberships }))}.signature`;
}

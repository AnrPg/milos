import { beforeEach, describe, expect, it, vi } from "vitest";

const phoenix = vi.hoisted(() => {
  type Receiver = (payload?: unknown) => void;
  const channels: MockChannel[] = [];

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
    ) {}

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

  return { Socket: MockSocket, channels };
});

vi.mock("phoenix", () => ({ Socket: phoenix.Socket }));

import { ChannelPushError, joinChannelWithPush, resetRealtimeSocket } from "@/lib/realtime";

describe("joinChannelWithPush", () => {
  beforeEach(() => {
    phoenix.channels.length = 0;
    resetRealtimeSocket();
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
});

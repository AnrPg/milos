declare module "phoenix" {
  export type ChannelJoinResult = {
    receive(status: "ok" | "error" | "timeout", callback: (response?: unknown) => void): ChannelJoinResult;
  };

  export interface Channel {
    on(event: string, callback: (payload: unknown) => void): void;
    push(event: string, payload: Record<string, unknown>): ChannelJoinResult;
    join(): ChannelJoinResult;
    leave(): void;
  }

  export class Socket {
    constructor(endpoint: string, options?: { params?: Record<string, unknown> });
    connect(): void;
    disconnect(): void;
    channel(topic: string, params?: Record<string, unknown>): Channel;
  }
}

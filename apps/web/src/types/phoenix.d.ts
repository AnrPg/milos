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
    /** `params` may be a function: it is read at every (re)connect. */
    constructor(endpoint: string, options?: { params?: Record<string, unknown> | (() => Record<string, unknown>) });
    connect(): void;
    onOpen(callback: () => void): string;
    onClose(callback: (event?: unknown) => void): string;
    onError(callback: (error?: unknown) => void): string;
    disconnect(): void;
    channel(topic: string, params?: Record<string, unknown>): Channel;
  }
}

"use client";

// ADR-249: Tap to Pay at the desk. Inside the store apps, the app's own
// `PaleeVivaTerminal` plugin hands the server's sale request to the
// «Viva.com Terminal» app (Android intent / iOS URL scheme
// `vivapayclient://pay/v1`) and brings its answer back on
// `palee-terminal://result`. The answer is only passed on to the API
// (`POST /admin/payments/terminal/result`), which confirms it with Viva
// before any money is recorded. The «Είσπραξη» screens (ADR-272) live in
// components/admin/collect.
import { hasCapability } from "./index";

/** The callback the terminal app answers on (the API's `payment_terminal_app` callback). */
export const TERMINAL_CALLBACK = "palee-terminal://result";

/** Schemes the phone may hand a request to: Viva's app, and the sandbox in dev/test. */
export const TERMINAL_SCHEMES = ["vivapayclient://pay/v1", "palee-sandbox-terminal://pay/v1"] as const;

/** The request as the API returns it in `payment.app_request`. */
export type TerminalAppRequest = {
  scheme: string;
  params: Record<string, string>;
  url?: string;
};

/** What the terminal app returned, ready for the API's result endpoint. */
export type TerminalResultBody = {
  reference: string;
  status: string;
  transaction_id: string | null;
  message: string | null;
};

export type TerminalCallback = {
  /** Every query parameter of the callback, decoded where it could be. */
  params: Record<string, string>;
  body: TerminalResultBody | null;
};

export type PaleeVivaTerminalPlugin = {
  /** Whether the terminal app is installed and can be asked to take a card. */
  isAvailable(): Promise<{ available: boolean }>;
  /** Hands the sale request to the terminal app; resolves once it was opened. */
  pay(options: { scheme: string; params: Record<string, string> }): Promise<{ launched: boolean }>;
  /**
   * The last callback the app received and nobody took yet (it survives the
   * iOS reset to the idle screen when the PIN pad shows, and process death).
   */
  takePendingResult(): Promise<{ url: string | null }>;
  addListener(event: "result", listener: (event: { url: string }) => void): Promise<{ remove: () => Promise<void> }>;
};

/** Whether this device can hand a request to the terminal app (the store apps only). */
export function tapToPaySupported(): boolean {
  return hasCapability("tapToPay");
}

function encode(value: string): string {
  // Strict RFC 3986: also `!'()*`, so a description never breaks the URL.
  return encodeURIComponent(value).replace(/[!'()*]/g, (character) => `%${character.charCodeAt(0).toString(16).toUpperCase()}`);
}

/**
 * The URL the phone opens for a sale request: the scheme and every
 * parameter, percent-encoded, in the order the API gave them.
 */
export function buildSaleUrl(request: TerminalAppRequest): string {
  if (!(TERMINAL_SCHEMES as readonly string[]).includes(request.scheme)) {
    throw new Error("terminal_scheme_not_allowed");
  }
  const query = Object.entries(request.params)
    .filter(([, value]) => typeof value === "string" && value !== "")
    .map(([key, value]) => `${encode(key)}=${encode(value)}`)
    .join("&");
  return query === "" ? request.scheme : `${request.scheme}?${query}`;
}

function decode(value: string): string {
  // Viva's samples leave spaces and `+` (base64) unencoded: keep `+` as it is.
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

/**
 * Reads the terminal app's callback (`palee-terminal://result?status=…`).
 * Returns null for any other URL. `body` is null when the callback names no
 * request (no `clientTransactionId`).
 */
export function parseTerminalCallback(url: string, callback: string = TERMINAL_CALLBACK): TerminalCallback | null {
  const [base, ...rest] = url.split("?");
  if (base.replace(/\/+$/, "") !== callback.replace(/\/+$/, "")) return null;
  const query = rest.join("?").split("#")[0];
  const params: Record<string, string> = {};
  for (const pair of query.split("&")) {
    if (pair === "") continue;
    const at = pair.indexOf("=");
    const key = decode(at === -1 ? pair : pair.slice(0, at));
    if (key === "" || key in params) continue;
    params[key] = at === -1 ? "" : decode(pair.slice(at + 1));
  }
  const reference = params.clientTransactionId?.trim();
  const optional = (value: string | undefined) => (value && value.trim() !== "" ? value.trim() : null);
  return {
    params,
    body: reference
      ? {
          reference,
          status: optional(params.status) ?? "error",
          transaction_id: optional(params.transactionId),
          message: optional(params.message),
        }
      : null,
  };
}

let pluginPromise: Promise<PaleeVivaTerminalPlugin> | null = null;

/** The plugin the native shell already put on its bridge, if any. */
function bridgedPlugin(): PaleeVivaTerminalPlugin | null {
  if (typeof window === "undefined") return null;
  const bridge = (window as unknown as { Capacitor?: { Plugins?: Record<string, unknown> } }).Capacitor;
  const plugin = bridge?.Plugins?.PaleeVivaTerminal;
  return plugin && typeof plugin === "object" ? (plugin as PaleeVivaTerminalPlugin) : null;
}

export function vivaTerminalPlugin(): Promise<PaleeVivaTerminalPlugin> {
  const bridged = bridgedPlugin();
  if (bridged) return Promise.resolve(bridged);
  pluginPromise ??= import("@capacitor/core").then(({ registerPlugin }) => registerPlugin<PaleeVivaTerminalPlugin>("PaleeVivaTerminal"));
  return pluginPromise;
}

/** Hands the API's sale request to the terminal app. */
export async function launchTerminalSale(request: TerminalAppRequest, plugin?: PaleeVivaTerminalPlugin): Promise<void> {
  buildSaleUrl(request); // refuses an unknown scheme before anything opens
  const native = plugin ?? (await vivaTerminalPlugin());
  const { launched } = await native.pay({ scheme: request.scheme, params: request.params });
  if (!launched) throw new Error("terminal_app_unavailable");
}

/** A callback the app received while the web app was not listening (iOS reset, process death). */
export async function takePendingTerminalResult(plugin?: PaleeVivaTerminalPlugin): Promise<TerminalCallback | null> {
  const native = plugin ?? (await vivaTerminalPlugin());
  const { url } = await native.takePendingResult();
  return url ? parseTerminalCallback(url) : null;
}

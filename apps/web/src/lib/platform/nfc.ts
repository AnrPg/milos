"use client";

// ADR-173: writing a location's NFC door tag from «Ρυθμίσεις › Τοποθεσία».
// Inside the store apps through the app's own `MilosNfc` plugin (Core NFC on
// iOS, Android's NFC adapter); in Chrome on Android through Web NFC. Reading
// a tag needs no code: the tag holds an https link under /c/, which the phone
// opens in the app (universal link / App Link) or in the browser.
import { hasCapability } from "./index";

export type MilosNfcPlugin = {
  isAvailable(): Promise<{ available: boolean; enabled: boolean }>;
  /** Waits for a tag near the phone and writes one URL record to it. */
  write(options: { url: string }): Promise<void>;
};

type NdefWriter = { write(message: { records: { recordType: string; data: string }[] }): Promise<void> };
type NdefReaderConstructor = new () => NdefWriter;

export type NfcWriter = "app" | "web" | null;

function webNdef(): NdefReaderConstructor | null {
  if (typeof window === "undefined") return null;
  const candidate = (window as unknown as { NDEFReader?: NdefReaderConstructor }).NDEFReader;
  return typeof candidate === "function" ? candidate : null;
}

/** How this device can write a tag: the app's plugin, Web NFC, or not at all. */
export function nfcWriter(): NfcWriter {
  if (hasCapability("nfc")) return "app";
  return webNdef() ? "web" : null;
}

let pluginPromise: Promise<MilosNfcPlugin> | null = null;

export function nfcPlugin(): Promise<MilosNfcPlugin> {
  pluginPromise ??= import("@capacitor/core").then(({ registerPlugin }) => {
    const native = registerPlugin<MilosNfcPlugin>("MilosNfc");
    return { isAvailable: () => native.isAvailable(), write: (options) => native.write(options) };
  });
  return pluginPromise;
}

/** Writes the tag link; rejects when the person cancels or the tag can't be written. */
export async function writeNfcTag(url: string, writer: NfcWriter = nfcWriter(), plugin?: MilosNfcPlugin): Promise<void> {
  if (writer === "app") {
    await (plugin ?? (await nfcPlugin())).write({ url });
    return;
  }
  const Reader = webNdef();
  if (writer === "web" && Reader) {
    await new Reader().write({ records: [{ recordType: "url", data: url }] });
    return;
  }
  throw new Error("nfc_unavailable");
}

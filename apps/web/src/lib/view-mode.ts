"use client";

import { useSyncExternalStore } from "react";

import type { View } from "@/lib/role-navigation";

// "My training" (ADR-103): a staff member who is also a client of the gym
// switches the whole app to their client pages and back. Per browser.
const KEY = "milos.view";
const listeners = new Set<() => void>();

function read(): View {
  try {
    return window.localStorage.getItem(KEY) === "client" ? "client" : "staff";
  } catch {
    return "staff";
  }
}

export function setView(view: View) {
  try {
    window.localStorage.setItem(KEY, view);
  } catch {}
  listeners.forEach((listener) => listener());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useView(): View {
  return useSyncExternalStore(subscribe, read, () => "staff");
}

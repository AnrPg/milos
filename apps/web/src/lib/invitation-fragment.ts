"use client";

import { useSyncExternalStore } from "react";

/**
 * ADR-209: the invitation token in the page's fragment (`#token=…`). Emailed
 * invitation links keep it there, so it never reaches a server log; the
 * server render sees none.
 */
export function useFragmentInvitationToken(): string {
  return useSyncExternalStore(subscribe, readFragmentToken, () => "");
}

export function readFragmentToken(): string {
  return new URLSearchParams(window.location.hash.replace(/^#/, "")).get("token")?.trim() ?? "";
}

function subscribe(onChange: () => void) {
  window.addEventListener("hashchange", onChange);
  return () => window.removeEventListener("hashchange", onChange);
}

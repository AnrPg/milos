"use client";

import { useCallback, useEffect, useState } from "react";

import type { EventForm } from "@/components/events/events";
import {
  draftFromState,
  draftWorthKeeping,
  eventWizardDraftKey,
  parseEventWizardDraft,
  type EventWizardDraft,
  type EventWizardState,
} from "@/lib/event-wizard";

/** Storage can be missing or throw (private windows, blocked site data); a draft is a convenience only. */
function read(key: string | null): EventWizardDraft | null {
  if (!key) return null;
  try {
    return parseEventWizardDraft(window.localStorage.getItem(eventWizardDraftKey(key)), new Date());
  } catch {
    return null;
  }
}

function write(key: string, value: string | null) {
  try {
    if (value === null) window.localStorage.removeItem(eventWizardDraftKey(key));
    else window.localStorage.setItem(eventWizardDraftKey(key), value);
  } catch {
    // Not kept: the wizard works the same without a draft.
  }
}

/**
 * A new event's draft on this device, per host (`hostKey`; null keeps
 * none, as when editing). A draft found for the host is offered first and
 * nothing is saved over it until they continue it or start over.
 */
export function useEventWizardDraft(hostKey: string | null, state: EventWizardState, blank: EventForm) {
  const [entry, setEntry] = useState(() => ({ key: hostKey, offer: read(hostKey) }));
  // A new host: look for its draft (state adjusted while rendering, not in an effect).
  if (entry.key !== hostKey) setEntry({ key: hostKey, offer: read(hostKey) });
  const offer = entry.key === hostKey ? entry.offer : null;
  const [savedAt, setSavedAt] = useState<Date | null>(null);
  const [stopped, setStopped] = useState(false);

  useEffect(() => {
    if (!hostKey || offer || stopped) return;
    const timer = window.setTimeout(() => {
      const keep = draftWorthKeeping(state, blank);
      const now = new Date();
      write(hostKey, keep ? JSON.stringify(draftFromState(state, now)) : null);
      setSavedAt(keep ? now : null);
    }, 400);
    return () => window.clearTimeout(timer);
  }, [hostKey, offer, stopped, state, blank]);

  const dismiss = useCallback(() => setEntry({ key: hostKey, offer: null }), [hostKey]);
  const discard = useCallback(() => {
    if (hostKey) write(hostKey, null);
    setEntry({ key: hostKey, offer: null });
    setSavedAt(null);
  }, [hostKey]);
  /** After publishing: drop the draft and keep no other. */
  const clear = useCallback(() => {
    setStopped(true);
    if (hostKey) write(hostKey, null);
    setSavedAt(null);
  }, [hostKey]);

  return { offer, savedAt, dismiss, discard, clear };
}

"use client";

import { useQuery } from "@tanstack/react-query";
import { useEffect, useState } from "react";

import { fetchTerminalAvailability, postTerminalResult, type TerminalPayment } from "@/api/desk-collect";
import { useSession } from "@/components/session-provider";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { tapToPaySupported, takePendingTerminalResult, vivaTerminalPlugin } from "@/lib/platform/viva-terminal";
import { FRESHNESS } from "@/lib/query-policy";

/** Whether the box can take Tap to Pay, and why not (a setting: `reference` freshness, ADR-215). */
export function useTerminalAvailability(enabled = true) {
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const slug = useOrganizationSlug();
  return useQuery({
    queryKey: ["admin", "payments", "terminal", "availability", slug],
    enabled: Boolean(token) && enabled,
    staleTime: FRESHNESS.reference,
    queryFn: () => fetchTerminalAvailability(token!),
  });
}

/** Whether this phone has the «Viva.com Terminal» app (null while asking). */
export function useTerminalAppInstalled(supported: boolean): boolean | null {
  const [installed, setInstalled] = useState<boolean | null>(null);
  useEffect(() => {
    if (!supported) return;
    let cancelled = false;
    vivaTerminalPlugin()
      .then((plugin) => plugin.isAvailable())
      .then(({ available }) => {
        if (!cancelled) setInstalled(available);
      })
      .catch(() => {
        if (!cancelled) setInstalled(false);
      });
    return () => {
      cancelled = true;
    };
  }, [supported]);
  return supported ? installed : false;
}

// One take of the pending result per page load: the plugin hands it out
// once, and a remount (React strict mode) must not lose it.
let recovery: Promise<TerminalPayment | null> | null = null;

/**
 * iOS shows its idle screen while the card PIN is typed, and the web app
 * starts again when the terminal app answers. The answer waits in the plugin
 * (`takePendingResult`); it is passed on to the API at once, and the payment
 * it belongs to comes back for the «Μια πληρωμή γύρισε από τη Viva» card.
 */
export function useRecoveredPayment(enabled: boolean): TerminalPayment | null {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [payment, setPayment] = useState<TerminalPayment | null>(null);
  useEffect(() => {
    if (!enabled || !token || !tapToPaySupported()) return;
    let cancelled = false;
    recovery ??= takePendingTerminalResult()
      .then((callback) => (callback?.body ? postTerminalResult(token, callback.body).then((response) => response.payment) : null))
      .catch(() => null);
    void recovery.then((found) => {
      if (!cancelled) setPayment(found);
    });
    return () => {
      cancelled = true;
    };
  }, [enabled, token]);
  return payment;
}

/** Test seam: forget the pending result taken on this page load. */
export function resetRecoveryForTests() {
  recovery = null;
}

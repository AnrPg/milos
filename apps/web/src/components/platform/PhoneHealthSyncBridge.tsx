"use client";

// ADR-172: inside the store app, a connected Apple Health or Health Connect
// row syncs on its own when the app opens and each time the person comes back
// to it, at most every 15 minutes. Renders nothing and does nothing in a
// browser or in an app build without the health plugin. No background reads:
// the phone is only read while the app is in front.
import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";

import type { ConnectedDevices } from "@/api/check-in";
import { DEVICES_KEY, fetchDevices } from "@/api/devices";
import { refreshAfterImport } from "@/components/devices/device-queries";
import { phoneRowOf, withPhoneRow } from "@/components/devices/phone-health-model";
import { useSession } from "@/components/session-provider";
import { autoSyncDue, newCount, phoneHealthProvider, syncPhoneHealth } from "@/lib/platform/health";

type Removable = { remove: () => Promise<void> };

export function PhoneHealthSyncBridge() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();

  useEffect(() => {
    const provider = phoneHealthProvider();
    if (!provider || !token) return;
    let disposed = false;
    let handle: Removable | null = null;

    const run = async () => {
      const devices = await queryClient.fetchQuery({ queryKey: DEVICES_KEY, queryFn: () => fetchDevices(token), staleTime: 60_000 });
      const row = phoneRowOf(devices.integrations, provider);
      if (disposed || !row || row.status !== "connected" || !autoSyncDue(row.connection?.last_synced_at)) return;
      const result = await syncPhoneHealth(token, row);
      if (result.row) queryClient.setQueryData<ConnectedDevices>(DEVICES_KEY, (current) => withPhoneRow(current, result.row!));
      if (newCount(result.counts)) refreshAfterImport(queryClient);
    };
    // A failed sync waits for the next opening; the row shows the last good one.
    const attempt = () => void run().catch(() => undefined);

    attempt();
    void (async () => {
      const { App } = await import("@capacitor/app");
      const listener = await App.addListener("resume", attempt);
      if (disposed) void listener.remove();
      else handle = listener;
    })().catch(() => undefined);

    return () => {
      disposed = true;
      void handle?.remove();
    };
  }, [token, queryClient]);

  return null;
}

import type { QueryClient } from "@tanstack/react-query";

import { DEVICE_SUMMARY_KEY } from "@/api/devices";
import { JOURNAL_FEED_KEY } from "@/api/journal";

/** After a device brought something new: the journal card, the feed and Πρόοδος read again. */
export function refreshAfterImport(queryClient: QueryClient) {
  void queryClient.invalidateQueries({ queryKey: DEVICE_SUMMARY_KEY });
  void queryClient.invalidateQueries({ queryKey: JOURNAL_FEED_KEY });
  void queryClient.invalidateQueries({ queryKey: ["me", "daily-stats"] });
}

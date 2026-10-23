"use client";

import { useEffect, useState } from "react";

/** Ticks once a minute so "5 minutes ago" stays true while the page is open. */
export function useNow() {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, []);
  return now;
}

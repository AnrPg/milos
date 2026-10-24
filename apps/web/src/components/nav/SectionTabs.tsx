"use client";

import Link from "next/link";

import type { SectionGroup } from "@/lib/role-navigation";
import { activeItemId } from "@/lib/role-navigation";

// The tab strip of a page group (Coaching, Training, Journal): each tab is an
// existing page, so the pages themselves stay as they are (ADR-103).
export function SectionTabs({
  group,
  pathname,
  hrefFor,
  labelFor,
}: {
  group: SectionGroup;
  pathname: string;
  hrefFor: (href: string, scoped?: boolean) => string;
  labelFor: (labelKey: string) => string;
}) {
  const active = activeItemId(pathname, group.tabs);
  return (
    <nav
      data-tabs
      aria-label={labelFor(group.id)}
      className="flex w-full items-center gap-1 overflow-x-auto px-2 pb-1.5 sm:px-5"
      style={{ scrollbarWidth: "none" }}
    >
      {group.tabs.map((tab) => {
        const current = tab.id === active;
        return (
          // Full prefetch: switching tabs renders from the client cache with
          // no server round trip (staleTimes in next.config.ts).
          <Link
            key={tab.id}
            href={hrefFor(tab.href, tab.scoped)}
            prefetch
            aria-current={current ? "page" : undefined}
            className="shrink-0 whitespace-nowrap rounded-full px-3 py-1 text-xs font-semibold transition-colors"
            style={{
              background: current ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "transparent",
              color: current ? "var(--primary-strong)" : "var(--dim)",
              border: `1px solid ${current ? "color-mix(in srgb, var(--primary) 30%, transparent)" : "var(--border)"}`,
            }}
          >
            {labelFor(tab.labelKey)}
          </Link>
        );
      })}
    </nav>
  );
}

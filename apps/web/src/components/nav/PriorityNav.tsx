"use client";

import Link from "next/link";
import { useEffect, useLayoutEffect, useRef, useState } from "react";

export type PriorityNavLink = { id: string; href: string; label: string };

const GAP = 4;
const useIsomorphicLayoutEffect = typeof window === "undefined" ? useEffect : useLayoutEffect;

// Links keep their priority order; whatever does not fit the bar's width in
// the current language moves into the last ("More") menu, so the bar never
// wraps or scrolls on a narrow phone (ADR-103).
export function PriorityNav({
  links,
  activeId,
  moreLabel,
}: {
  links: PriorityNavLink[];
  activeId: string | null;
  moreLabel: string;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const [visibleCount, setVisibleCount] = useState(links.length);
  const [open, setOpen] = useState(false);
  const signature = links.map((link) => link.id + link.label).join("|");

  useIsomorphicLayoutEffect(() => {
    const container = containerRef.current;
    const measure = measureRef.current;
    if (!container || !measure) return;

    const compute = () => {
      const widths = Array.from(measure.children).map((child) => (child as HTMLElement).offsetWidth);
      const moreWidth = widths.pop() ?? 0;
      const available = container.clientWidth;
      const total = widths.reduce((sum, width) => sum + width + GAP, 0);
      if (total <= available) {
        setVisibleCount(widths.length);
        return;
      }
      let used = moreWidth;
      let count = 0;
      for (const width of widths) {
        if (used + width + GAP > available) break;
        used += width + GAP;
        count += 1;
      }
      setVisibleCount(count);
    };

    compute();
    const observer = new ResizeObserver(compute);
    observer.observe(container);
    return () => observer.disconnect();
  }, [signature]);

  useEffect(() => {
    if (!open) return;
    const close = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) setOpen(false);
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", escape);
    };
  }, [open]);

  const visible = links.slice(0, visibleCount);
  const overflow = links.slice(visibleCount);
  const overflowActive = overflow.some((link) => link.id === activeId);
  const pill = "whitespace-nowrap rounded-full px-3 py-1 text-sm font-semibold transition-colors";

  return (
    <div ref={containerRef} className="relative flex min-w-0 flex-1 items-center">
      <div ref={measureRef} aria-hidden="true" className="invisible absolute start-0 top-0 flex gap-1" style={{ pointerEvents: "none" }}>
        {links.map((link) => (
          <span key={link.id} className={pill}>{link.label}</span>
        ))}
        <span className={pill}>{moreLabel} ▾</span>
      </div>

      <div className="flex min-w-0 items-center gap-1">
        {visible.map((link) => {
          const active = link.id === activeId;
          return (
            <Link
              key={link.id}
              href={link.href}
              aria-current={active ? "page" : undefined}
              className={pill}
              style={{ background: active ? "var(--border)" : "transparent", color: active ? "var(--text)" : "var(--dim)" }}
            >
              {link.label}
            </Link>
          );
        })}
        {overflow.length > 0 ? (
          <div ref={menuRef} className="relative shrink-0">
            <button
              type="button"
              aria-expanded={open}
              aria-haspopup="true"
              onClick={() => setOpen((value) => !value)}
              className={pill}
              style={{
                background: overflowActive || open ? "var(--border)" : "transparent",
                color: overflowActive || open ? "var(--text)" : "var(--dim)",
              }}
            >
              {moreLabel} <span aria-hidden="true" className="text-xs">▾</span>
            </button>
            {open ? (
              <div
                className="absolute start-0 top-full mt-1 w-52 max-w-[calc(100vw-1rem)] rounded-2xl py-1.5 shadow-[0_20px_60px_rgba(0,0,0,0.7)]"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", zIndex: 100 }}
              >
                {overflow.map((link) => (
                  <Link
                    key={link.id}
                    href={link.href}
                    className="block px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-[color-mix(in_srgb,var(--text)_4%,transparent)]"
                    style={{ color: link.id === activeId ? "var(--primary)" : "var(--text)" }}
                    onClick={() => setOpen(false)}
                  >
                    {link.label}
                  </Link>
                ))}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
    </div>
  );
}

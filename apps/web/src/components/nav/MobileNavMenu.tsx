"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

import type { PriorityNavLink } from "@/components/nav/PriorityNav";

// Small screens: one ☰ button that opens every link of the bar as a vertical
// list (ADR-103). Larger screens use PriorityNav instead.
export function MobileNavMenu({
  links,
  activeId,
  label,
}: {
  links: PriorityNavLink[];
  activeId: string | null;
  label: string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const close = (event: MouseEvent) => {
      if (ref.current && !ref.current.contains(event.target as Node)) setOpen(false);
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

  if (links.length === 0) return null;

  return (
    <div ref={ref} className="relative shrink-0 sm:hidden">
      <button
        type="button"
        aria-expanded={open}
        aria-haspopup="true"
        aria-label={label}
        title={label}
        className="grid h-9 w-9 place-items-center rounded-full text-lg"
        style={{ background: open ? "var(--border)" : "transparent", color: "var(--text)" }}
        onClick={() => setOpen((value) => !value)}
      >
        <span aria-hidden="true">☰</span>
      </button>
      {open ? (
        <nav
          aria-label={label}
          className="absolute start-0 top-full mt-1 w-64 max-w-[calc(100vw-1rem)] rounded-2xl py-1.5 shadow-[var(--shadow-lg)]"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", zIndex: 100 }}
        >
          {links.map((link) => {
            const active = link.id === activeId;
            return (
              <Link
                key={link.id}
                href={link.href}
                aria-current={active ? "page" : undefined}
                className="block px-4 py-3 text-sm font-semibold transition-colors hover:bg-[color-mix(in_srgb,var(--text)_4%,transparent)]"
                style={{ color: active ? "var(--primary)" : "var(--text)" }}
                onClick={() => setOpen(false)}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>
      ) : null}
    </div>
  );
}

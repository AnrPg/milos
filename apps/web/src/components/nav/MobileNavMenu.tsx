"use client";

import Link from "next/link";
import { useRef, useState } from "react";

import type { PriorityNavLink } from "@/components/nav/PriorityNav";
import { Popover } from "@/components/ui/Popover";

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
  const buttonRef = useRef<HTMLButtonElement>(null);

  if (links.length === 0) return null;

  return (
    <div className="relative shrink-0 sm:hidden">
      <button
        ref={buttonRef}
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
      <Popover
        anchorRef={buttonRef}
        open={open}
        onClose={() => setOpen(false)}
        width={256}
        className="rounded-2xl py-1.5 shadow-[var(--shadow-lg)]"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <nav aria-label={label}>
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
      </Popover>
    </div>
  );
}

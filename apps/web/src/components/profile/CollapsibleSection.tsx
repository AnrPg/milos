"use client";

import { useEffect, useRef, useState } from "react";

/** A titled settings card that opens in place (Εγώ › Ρυθμίσεις, Κοινοποίηση & ορατότητα). */
export function CollapsibleSection({
  id,
  title,
  description,
  defaultOpen = false,
  children,
}: {
  id: string;
  title: string;
  description?: string;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);
  const sectionRef = useRef<HTMLElement>(null);

  // A link to /…#<id> (e.g. /me/settings#recovery-codes) opens this card and
  // brings it into view, also when the hash changes on the same page.
  useEffect(() => {
    function openFromHash() {
      if (window.location.hash !== `#${id}`) return;
      setOpen(true);
      window.requestAnimationFrame(() => sectionRef.current?.scrollIntoView({ block: "start", behavior: "smooth" }));
    }
    openFromHash();
    window.addEventListener("hashchange", openFromHash);
    return () => window.removeEventListener("hashchange", openFromHash);
  }, [id]);

  return (
    <section
      ref={sectionRef}
      id={id}
      className="scroll-mt-24 overflow-hidden rounded-[2.4rem]"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <button
        className="flex w-full items-center justify-between gap-4 p-8 text-start"
        type="button"
        onClick={() => setOpen((v) => !v)}
      >
        <div>
          <p
            className="text-sm font-semibold uppercase tracking-[0.24em]"
            style={{ color: "var(--primary)" }}
          >
            {title}
          </p>
          {description && (
            <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
              {description}
            </p>
          )}
        </div>
        <span className="text-xl font-light" style={{ color: "var(--dim)" }}>
          {open ? "−" : "+"}
        </span>
      </button>
      {open && (
        <div className="border-t px-8 pb-8 pt-6" style={{ borderColor: "var(--border)" }}>
          {children}
        </div>
      )}
    </section>
  );
}

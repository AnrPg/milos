"use client";

import { useId, useState } from "react";

import { useUiTranslations } from "@/i18n/ui";

export function HomeDisclosure({
  eyebrow,
  title,
  defaultOpen = true,
  actions,
  children,
}: {
  eyebrow: React.ReactNode;
  title: React.ReactNode;
  defaultOpen?: boolean;
  actions?: React.ReactNode;
  children: React.ReactNode;
}) {
  const i18n = useUiTranslations();
  const contentId = useId();
  const [open, setOpen] = useState(defaultOpen);

  return (
    <section className="overflow-hidden rounded-[2.2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex items-center gap-3 p-6">
        <button
          type="button"
          aria-expanded={open}
          aria-controls={contentId}
          onClick={() => setOpen((value) => !value)}
          className="flex min-w-0 flex-1 items-center justify-between gap-4 text-start"
        >
          <span className="min-w-0">
            <span className="block text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{eyebrow}</span>
            <span className="mt-3 block text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{title}</span>
          </span>
          <span className="shrink-0 text-sm font-semibold" style={{ color: "var(--dim)" }}>
            {open ? i18n("hide34d8b60") : i18n("showd97d1ee")}
          </span>
        </button>
        {actions ? <div className="flex shrink-0 items-center gap-2">{actions}</div> : null}
      </div>
      {open ? <div id={contentId} className="border-t px-6 pb-6 pt-5" style={{ borderColor: "var(--border)" }}>{children}</div> : null}
    </section>
  );
}

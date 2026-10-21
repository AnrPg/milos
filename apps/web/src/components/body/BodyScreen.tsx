"use client";

import type { ReactNode } from "react";
import { useTranslations } from "next-intl";

/** The frame of Σώμα's inner screens (new, edit, snapshot, compare, settings). */
export function BodyScreen({ titleKey, children }: { titleKey?: string; children: ReactNode }) {
  const t = useTranslations("Body");
  return (
    <main className="min-h-screen px-4 py-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-2xl flex-col gap-4">
        {titleKey ? <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t(titleKey)}</h2> : null}
        {children}
      </div>
    </main>
  );
}

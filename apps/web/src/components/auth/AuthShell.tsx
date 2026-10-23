"use client";

import type { ReactNode } from "react";

import { PaleeMark } from "@/components/branding/PaleeMark";
import { useUiTranslations } from "@/i18n/ui";

/** The centred card the signed-out pages share with the sign-in console. */
export function AuthShell({ title, children }: { title: string; children: ReactNode }) {
  const ui = useUiTranslations();

  return (
    <main className="flex min-h-screen items-center justify-center px-6 py-10" style={{ background: "var(--bg)" }}>
      <div className="w-full max-w-md">
        <div className="rounded-[2rem] p-7" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="mb-6 text-center">
            <PaleeMark className="mx-auto mb-3 h-12 w-12" />
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
              {ui("brandName")}
            </p>
            <h1 className="mt-2 text-2xl font-bold tracking-tight" style={{ color: "var(--text)" }}>
              {title}
            </h1>
          </div>
          {children}
        </div>
      </div>
    </main>
  );
}

export const primaryButtonClass = "w-full rounded-2xl px-4 py-3 font-semibold disabled:opacity-60";
export const primaryButtonStyle = { background: "var(--primary)", color: "var(--primary-contrast)" } as const;

/** A form-level message: an error, or (tone "success") a confirmation. */
export function AuthNotice({ children, tone = "error" }: { children: ReactNode; tone?: "error" | "success" }) {
  const accent = tone === "success" ? "var(--success)" : "var(--primary)";
  return (
    <p
      className="rounded-2xl px-4 py-3 text-sm"
      role={tone === "error" ? "alert" : "status"}
      style={{
        border: `1px solid color-mix(in srgb, ${accent} 25%, transparent)`,
        background: `color-mix(in srgb, ${accent} 8%, transparent)`,
        color: tone === "success" ? "var(--text)" : "var(--primary-strong)",
      }}
    >
      {children}
    </p>
  );
}

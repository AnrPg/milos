"use client";

import type { ReactNode, SVGProps } from "react";
import { useTranslations } from "next-intl";

import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

import { verifyErrorKey } from "./verify-model";

/**
 * Small shared pieces of the verification screens: line icons (stroke,
 * currentColor, never emoji), the button looks, a card, and the error
 * wording (the verification's own words for its codes, else the shared one).
 */
export type VerifyIconName = "check" | "clock" | "lock" | "qr" | "copy" | "camera" | "shield" | "close" | "phone" | "users" | "alert";

export function VerifyIcon({ name, size = 20, ...rest }: { name: VerifyIconName; size?: number } & SVGProps<SVGSVGElement>) {
  const common = {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
    focusable: false,
    ...rest,
  };
  switch (name) {
    case "check":
      return <svg {...common}><path d="m5 12.5 4.5 4.5L19 7.5" /></svg>;
    case "clock":
      return <svg {...common}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></svg>;
    case "lock":
      return <svg {...common}><rect x="5" y="10.5" width="14" height="10" rx="2" /><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" /></svg>;
    case "qr":
      return (
        <svg {...common}>
          <rect x="4" y="4" width="6" height="6" rx="1" />
          <rect x="14" y="4" width="6" height="6" rx="1" />
          <rect x="4" y="14" width="6" height="6" rx="1" />
          <path d="M14 14h2v2h-2zM18 18h2v2h-2zM14 18h2M18 14h2" />
        </svg>
      );
    case "copy":
      return <svg {...common}><rect x="8.5" y="8.5" width="11" height="11" rx="2" /><path d="M15.5 8.5V6a1.5 1.5 0 0 0-1.5-1.5H6A1.5 1.5 0 0 0 4.5 6v8A1.5 1.5 0 0 0 6 15.5h2.5" /></svg>;
    case "camera":
      return <svg {...common}><path d="M4 8.5A1.5 1.5 0 0 1 5.5 7h2l1.5-2h6l1.5 2h2A1.5 1.5 0 0 1 20 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5z" /><circle cx="12" cy="12.5" r="3.5" /></svg>;
    case "shield":
      return <svg {...common}><path d="M12 3.5 5 6v5.5c0 4.2 2.9 7.8 7 9 4.1-1.2 7-4.8 7-9V6z" /><path d="m9 12 2 2 4-4" /></svg>;
    case "close":
      return <svg {...common}><path d="M6 6l12 12M18 6 6 18" /></svg>;
    case "phone":
      return <svg {...common}><rect x="7" y="3" width="10" height="18" rx="2" /><path d="M11 17.5h2" /></svg>;
    case "users":
      return <svg {...common}><circle cx="9" cy="8.5" r="3.5" /><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6" /><path d="M16 5.2a3.5 3.5 0 0 1 0 6.6M18 14.4c1.8.9 3 2.9 3 5.6" /></svg>;
    case "alert":
      return <svg {...common}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5v5M12 16h.01" /></svg>;
  }
}

export const primaryButton =
  "inline-flex min-h-11 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-semibold disabled:opacity-50";
export const primaryStyle = { background: "var(--primary)", color: "var(--primary-contrast)" } as const;
export const secondaryStyle = { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" } as const;
export const dangerStyle = { background: "var(--danger)", color: "var(--danger-contrast)" } as const;
export const inputClass = "min-h-11 w-full rounded-xl px-3 text-base";
export const inputStyle = { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border-strong, var(--border))" } as const;

export function VerifyCard({ children, testId, label }: { children: ReactNode; testId?: string; label?: string }) {
  return (
    <section
      aria-label={label}
      data-testid={testId}
      className="flex min-w-0 flex-col gap-3 rounded-2xl p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      {children}
    </section>
  );
}

/** The verification's wording for an error, else the app's shared wording. */
export function useVerifyErrorText() {
  const t = useTranslations("PartnerVerify");
  const tUi = useUiTranslations();
  return (error: unknown): string | null => {
    if (!error) return null;
    const key = verifyErrorKey(error);
    return key ? t(key) : localizeError(error, tUi);
  };
}

/** An error under one field (variant "field") or for the whole form ("banner"). */
export function VerifyError({ error, field, id }: { error: unknown; field?: boolean; id?: string }) {
  const text = useVerifyErrorText()(error);
  if (!text) return null;
  return (
    <ErrorNotice variant={field ? "field" : "banner"} id={id}>
      {text}
    </ErrorNotice>
  );
}

"use client";




import {useUiTranslations} from "@/i18n/ui";
import { useEffect, type ReactNode } from "react";

export function SidePanel({
  title,
  subtitle,
  onClose,
  children,
  footer,
  width = "md:max-w-[520px]",
}: {
  title: string;
  subtitle?: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
  width?: string;
}) {
  const i18n = useUiTranslations();
  useEffect(() => {
    function handleKey(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [onClose]);

  return (
    <>
      <div
        className="fixed inset-0 z-40"
        style={{ background: "rgba(0,0,0,0.55)" }}
        onClick={onClose}
      />
      <div
        className={"fixed end-0 z-50 flex w-full flex-col overflow-hidden " + (width)}
        style={{ background: "var(--bg)", borderInlineStart: "1px solid var(--border)", top: "3.25rem", bottom: 0 }}
      >
        <div
          className="sticky top-0 z-10 flex items-start justify-between gap-4 px-6 py-5"
          style={{ background: "var(--bg)", borderBottom: "1px solid var(--border)" }}
        >
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>
              {subtitle ?? i18n("detail7c9a7c0")}
            </p>
            <h2 className="mt-2 text-xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
              {title}
            </h2>
          </div>
          <button
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            onClick={onClose}
            type="button"
          >
            {i18n("closebbfa773")}
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-6 py-6 space-y-6">
          {children}
        </div>

        {footer ? (
          <div
            className="px-6 py-4"
            style={{ borderTop: "1px solid var(--border)", background: "var(--bg)" }}
          >
            {footer}
          </div>
        ) : null}
      </div>
    </>
  );
}

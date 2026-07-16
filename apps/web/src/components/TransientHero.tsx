"use client";




import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useState, type ReactNode } from "react";

type Props = {
  children: ReactNode;
  collapsedTitle?: ReactNode;
  label?: string;
  showIntroLabel?: string;
  timeoutMs?: number;
};

function titleFromLabel(label: string, fallback: string) {
  const title = label.replace(/\s+introduction$/i, "").trim() || fallback;
  return title.charAt(0).toUpperCase() + title.slice(1);
}

export function TransientHero({
  children,
  collapsedTitle,
  label,
  showIntroLabel,
  timeoutMs,
}: Props) {
  const i18n = useUiTranslations();
  const resolvedLabel = label ?? i18n("pageIntroduction924d4b4");
  const resolvedShowIntroLabel = showIntroLabel ?? i18n("showIntro481366c");
  const [visible, setVisible] = useState(true);
  const [previewVisible, setPreviewVisible] = useState(false);

  useEffect(() => {
    if (!visible || !timeoutMs) return;

    const timeout = window.setTimeout(() => setVisible(false), timeoutMs);
    return () => window.clearTimeout(timeout);
  }, [timeoutMs, visible]);

  if (!visible) {
    return (
      <div onMouseLeave={() => setPreviewVisible(false)}>
        {previewVisible ? (
          <div aria-label={resolvedLabel}>{children}</div>
        ) : (
          <div className="flex items-center justify-between gap-3">
            <h1 className="min-w-0 truncate text-lg font-semibold tracking-tight sm:text-xl" style={{ color: "var(--primary)" }}>
              {collapsedTitle ?? titleFromLabel(resolvedLabel, i18n("pagefb06270"))}
            </h1>
            <button
              type="button"
              onClick={() => {
                setPreviewVisible(false);
                setVisible(true);
              }}
              onFocus={() => setPreviewVisible(true)}
              onBlur={() => setPreviewVisible(false)}
              onMouseEnter={() => setPreviewVisible(true)}
              className="rounded-full px-3 py-1.5 text-[11px] font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--dim)" }}
              aria-label={i18n("showd97d1ee") + resolvedLabel}
            >
              {resolvedShowIntroLabel}
            </button>
          </div>
        )}
      </div>
    );
  }

  return <div aria-label={resolvedLabel}>{children}</div>;
}

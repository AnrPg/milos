"use client";

import { useTranslations } from "next-intl";

import { HubCard, HubPage } from "@/components/member-app/HubParts";

const LINES = [
  { id: "emergency", number: "112" },
  { id: "suicide", number: "1018" },
  { id: "mental", number: "10306" },
] as const;

/**
 * Help lines, as information (board 15 q5 A): Palee is not a medical or
 * crisis service, so this page only lists who can help and how to reach
 * them. No advice, no assessment.
 */
export function SupportLinesPage() {
  const t = useTranslations("Buddy");
  return (
    <HubPage title={t("linesTitle")}>
      <HubCard>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("linesIntro")}</p>
      </HubCard>
      <HubCard eyebrow={t("linesGreece")}>
        <ul className="flex flex-col gap-3" data-testid="support-lines">
          {LINES.map((line) => (
            <li key={line.id} className="flex items-center justify-between gap-3">
              <span className="min-w-0">
                <span className="block text-sm font-bold" style={{ color: "var(--text)" }}>{t(["line", line.id].join("."))}</span>
                <span className="block text-xs" style={{ color: "var(--dim)" }}>{t(["lineHint", line.id].join("."))}</span>
              </span>
              <a
                href={`tel:${line.number}`}
                className="inline-flex min-h-11 shrink-0 items-center rounded-2xl px-4 text-sm font-bold tabular-nums"
                style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
              >
                {line.number}
              </a>
            </li>
          ))}
        </ul>
      </HubCard>
      <p className="px-1 text-xs leading-5" style={{ color: "var(--dim)" }}>{t("linesNote")}</p>
    </HubPage>
  );
}

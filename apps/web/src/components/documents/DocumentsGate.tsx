"use client";

import { useTranslations } from "next-intl";

import { BackButton } from "@/components/ui/BackLink";

import { gateReady, stepKey, type GateStep } from "./documents-model";
import { HealthUpload } from "./HealthUpload";
import { MY_HEALTH_API, StatusMark, useBoxName } from "./MyDocuments";
import { SignDocument } from "./SignDocument";

/**
 * The booking answered 409 `documents_required` (ADR-252 §6). Mockup s7,
 * option B: the booking sheet lists what is missing, each row opens «read
 * and sign» or the certificate upload in the same sheet, a done row turns
 * ✓, and «Κράτηση» (the sheet's footer, see `gateBookEnabled`) books right
 * after. Controlled by the sheet: it holds `done` and the open step.
 */
export function DocumentsGate({
  steps,
  done,
  openKey,
  onOpen,
  onDone,
}: {
  steps: GateStep[];
  done: ReadonlySet<string>;
  openKey: string | null;
  onOpen: (key: string | null) => void;
  onDone: (key: string) => void;
}) {
  const t = useTranslations("Documents");
  const boxName = useBoxName();
  const open = steps.find((step) => stepKey(step) === openKey) ?? null;

  if (open) {
    const key = stepKey(open);
    return (
      <div className="flex flex-col gap-2" data-testid="documents-gate-step">
        <BackButton onClick={() => onOpen(null)} className="min-h-10 self-start text-sm font-semibold">
          {t("backToBooking")}
        </BackButton>
        {open.kind === "document" ? (
          <SignDocument
            templateId={open.templateId}
            boxName={boxName}
            onSigned={() => {
              onDone(key);
              onOpen(null);
            }}
          />
        ) : (
          <HealthUpload
            api={MY_HEALTH_API}
            onUploaded={() => {
              onDone(key);
              onOpen(null);
            }}
          />
        )}
      </div>
    );
  }

  const ready = gateReady(steps, done);
  return (
    <div className="flex flex-col gap-2" data-testid="documents-gate">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {ready ? t("gateReady") : t("gateMissing")}
      </p>
      <ul className="overflow-hidden rounded-2xl" style={{ border: "1px solid var(--border)" }}>
        {steps.map((step, index) => {
          const key = stepKey(step);
          const isDone = done.has(key);
          const title = step.kind === "document" ? step.title : t("healthTitle");
          const detail =
            step.kind === "document"
              ? step.reason === "resign_required"
                ? t("gateResign")
                : t("gateSign")
              : step.status === "expired"
                ? t("gateHealthExpired")
                : t("gateHealthMissing");
          return (
            <li key={key} style={index > 0 ? { borderTop: "1px solid var(--border)" } : undefined}>
              <button
                type="button"
                disabled={isDone}
                onClick={() => onOpen(key)}
                className="flex min-h-14 w-full items-center justify-between gap-3 px-4 py-3 text-left"
                style={{ background: "var(--panel)" }}
                data-testid={`gate-step-${key}`}
              >
                <span className="flex min-w-0 flex-col">
                  <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {title}
                  </span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {isDone ? t("gateDone") : detail}
                  </span>
                </span>
                {isDone ? (
                  <StatusMark tone="ok">✓</StatusMark>
                ) : (
                  <span aria-hidden="true" style={{ color: "var(--dim)" }}>
                    ›
                  </span>
                )}
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

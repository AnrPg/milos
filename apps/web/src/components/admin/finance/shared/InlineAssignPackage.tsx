"use client";





import { useRef, useState } from "react";

import type { FinanceRecord } from "@/api/finance";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Popover } from "@/components/ui/Popover";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

interface Props {
  userId: string;
  currentCode: string | null;
  currentLabel?: string | null;
  packages: FinanceRecord[];
  pending: boolean;
  /** Resolves once the package is assigned; a rejection keeps the menu open with the reason. */
  onAssign: (packageId: string) => Promise<unknown>;
}

/**
 * The ledger's «Ανάθεση» menu for a πακέτο συνδρομής. It is a ui/Popover, so
 * a press on the package list (its own portal) counts as inside the menu.
 */
export function InlineAssignPackage({ currentCode, currentLabel, packages, pending, onAssign }: Props) {
  const i18n = useUiTranslations();
  const [open, setOpen] = useState(false);
  const [selectedId, setSelectedId] = useState("");
  const [error, setError] = useState<unknown>(null);
  const ref = useRef<HTMLDivElement>(null);

  function close() {
    setOpen(false);
    setSelectedId("");
    setError(null);
  }

  async function handleAssign() {
    if (!selectedId) return;
    setError(null);
    try {
      await onAssign(selectedId);
      close();
    } catch (reason) {
      setError(reason);
    }
  }

  return (
    <div ref={ref} className="relative inline-block">
      {currentLabel || currentCode ? (
        <button
          type="button"
          onClick={() => (open ? close() : setOpen(true))}
          className="group flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold transition-opacity hover:opacity-70"
          style={{ background: "var(--border)", color: "var(--text-soft)" }}
          title={i18n("changePackage8621cbc")}
        >
          {currentLabel || currentCode}
          <span className="opacity-0 group-hover:opacity-60 transition-opacity text-[10px]">✎</span>
        </button>
      ) : (
        <button
          type="button"
          onClick={() => (open ? close() : setOpen(true))}
          className="rounded-full px-3 py-1 text-xs font-semibold transition-opacity hover:opacity-80"
          style={{
            border: "1px solid color-mix(in srgb, var(--primary) 35%, transparent)",
            color: "var(--dim)",
            background: "transparent",
          }}
        >
          {i18n("assign23afc22")}
        </button>
      )}

      <Popover
        anchorRef={ref}
        open={open}
        onClose={close}
        minWidth={240}
        role="dialog"
        ariaLabel={i18n("assign2444928")}
        className="rounded-xl p-3 shadow-xl"
        style={{
          background: "var(--panel-raised)",
          border: "1px solid var(--border-strong)",
          boxShadow: "var(--shadow-md)",
        }}
      >
        <Select
          value={selectedId}
          onValueChange={(value) => setSelectedId(value)}
          className="mb-3 w-full rounded-lg px-3 py-2.5 text-sm"
          style={{ background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }}
        >
          <option value="">{i18n("selectPackage02bf832")}</option>
          {packages.map((pkg) => (
            <option
              key={String(pkg.id)}
              value={String(pkg.id)}
              disabled={pkg.active === false}
            >
              {String(pkg.name || pkg.code)}
              {pkg.active === false ? i18n("inactive0e9b582") : ""}
            </option>
          ))}
        </Select>
        <button
          type="button"
          onClick={handleAssign}
          disabled={!selectedId || pending}
          className="w-full rounded-lg px-3 py-2.5 text-sm font-semibold transition-opacity disabled:opacity-40"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {pending ? i18n("assigning4d16a1a") : i18n("assign2444928")}
        </button>
        {error ? (
          <ErrorNotice variant="field" className="mt-2">
            {localizeError(error, i18n)}
          </ErrorNotice>
        ) : null}
      </Popover>
    </div>
  );
}

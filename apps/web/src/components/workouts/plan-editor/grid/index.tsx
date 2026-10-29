"use client";

/**
 * PLACEHOLDER (agent 3): stands in for the exercise grid that agent 4 builds
 * in this folder (branch plan/4-grid). Agent 3 does not edit it further; the
 * real `PlanGrid` replaces this file when plan/4-grid is merged.
 */
import { focusKey, usePlanEditorStore, type PlanEditorSection } from "@/stores/structured-plan";

export function PlanGrid({ section }: { section: PlanEditorSection }) {
  const updateRow = usePlanEditorStore((s) => s.updateRow);
  return (
    <div data-testid="plan-grid" className="flex flex-col gap-1">
      {section.plan.blocks.flat().map((row) => (
        <div key={row.id} data-testid={`plan-row-${row.id}`} data-row={row.id}>
          {row.kind === "ex" ? (
            <input
              data-k={focusKey.row(row.id, "name")}
              aria-label={row.name || row.id}
              value={row.name}
              onChange={(e) => updateRow(row.id, { name: e.target.value })}
              className="w-full rounded-lg border px-2 py-1 text-sm"
              style={{ background: "var(--control-bg)", borderColor: "var(--control-border)", color: "var(--text)" }}
            />
          ) : (
            <span data-k={focusKey.row(row.id, "name")} tabIndex={-1}>{row.dose}</span>
          )}
        </div>
      ))}
    </div>
  );
}

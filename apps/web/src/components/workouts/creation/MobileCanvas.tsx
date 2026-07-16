"use client";




import {useUiTranslations} from "@/i18n/ui";
import type { ScaleLevel } from "@/api/workouts";
import { useWorkoutCreationStore } from "@/stores/workout-creation";

import { LeftPanel } from "./LeftPanel";
import { MiddlePanel } from "./MiddlePanel";
import { RightPanel } from "./RightPanel";

type Props = {
  scaleLevels: ScaleLevel[];
};

export function MobileCanvas({ scaleLevels }: Props) {
  const i18n = useUiTranslations();
  const { mobileView, setMobileView } = useWorkoutCreationStore();

  return (
    <div className="relative flex flex-1 flex-col overflow-hidden">
      {mobileView === "exercises" ? (
        <button
          onClick={() => setMobileView("sections")}
          className="px-4 py-2 text-left text-sm"
          style={{ color: "var(--accent)" }}
        >
          {i18n("sectionsfcb5b85")}
        </button>
      ) : null}

      <div className="flex-1 overflow-hidden">
        {mobileView === "sections" ? (
          <LeftPanel mobile onSectionSelected={() => setMobileView("exercises")} />
        ) : null}
        {mobileView === "exercises" ? <MiddlePanel scaleLevels={scaleLevels} /> : null}
        {mobileView === "preview" ? <RightPanel scaleLevels={scaleLevels} mobile /> : null}
      </div>

      <div className="flex shrink-0 border-t" style={{ borderColor: "var(--dim)", background: "var(--panel)" }}>
        {(["sections", "exercises"] as const).map((view) => (
          <button
            key={view}
            onClick={() => setMobileView(view)}
            className="flex-1 py-3 text-xs font-bold uppercase tracking-widest"
            style={{ color: mobileView === view ? "var(--accent)" : "var(--dim)" }}
          >
            {view === "sections" ? i18n("sectionsfcb5b85") : i18n("exercises0ee6e81")}
          </button>
        ))}
        <button
          onClick={() => setMobileView("preview")}
          className="flex-1 py-3 text-xs font-bold uppercase tracking-widest"
          style={{ color: mobileView === "preview" ? "var(--lime)" : "var(--dim)" }}
        >
          {i18n("previewf1fbb2b")}
        </button>
      </div>
    </div>
  );
}

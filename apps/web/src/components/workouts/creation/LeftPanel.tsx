"use client";




import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef } from "react";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";

import { useWorkoutCreationStore } from "@/stores/workout-creation";

import { SectionChip } from "./SectionChip";
import { SectionConfig } from "./SectionConfig";

type Props = {
  onSectionSelected?: () => void;
  mobile?: boolean;
  showAllSections?: boolean;
};

export function LeftPanel({ onSectionSelected, mobile = false, showAllSections = false }: Props) {
  const i18n = useUiTranslations();
  const {
    sections,
    selectedSectionId,
    sectionConfigOpen,
    leftCollapsed,
    addSection,
    selectSection,
    setSectionConfigOpen,
    setLeftCollapsed,
  } = useWorkoutCreationStore();

  const panelRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (mobile) return;

    function handleMouseDown(event: MouseEvent) {
      if (panelRef.current && !panelRef.current.contains(event.target as Node)) {
        setSectionConfigOpen(false);
      }
    }

    document.addEventListener("mousedown", handleMouseDown);
    return () => document.removeEventListener("mousedown", handleMouseDown);
  }, [mobile, setSectionConfigOpen]);

  // Scroll list to top when an exercise drag starts so the first section is reachable
  useEffect(() => {
    if (showAllSections && listRef.current) {
      listRef.current.scrollTop = 0;
    }
  }, [showAllSections]);

  const selectedSection = sections.find((section) => section.localId === selectedSectionId) ?? null;

  if (!mobile && leftCollapsed) {
    return (
      <div
        className="flex w-10 shrink-0 cursor-pointer flex-col items-center justify-center"
        style={{ background: "var(--panel)", borderInlineEnd: "1px solid var(--dim)" }}
        onClick={() => setLeftCollapsed(false)}
      >
        <span
          className="text-xs font-bold uppercase tracking-widest"
          style={{
            writingMode: "vertical-rl",
            transform: "rotate(180deg)",
            color: "var(--muted)",
          }}
        >
          {i18n("sections7ff5a6d")}
        </span>
        <span className="mt-2 text-xs" style={{ color: "var(--muted)" }}>
          &gt;
        </span>
      </div>
    );
  }

  return (
    <div
      ref={panelRef}
      className={"flex " + (mobile ? "w-full" : "w-64 shrink-0") + " flex-col overflow-hidden"}
      style={{ background: "var(--panel)", borderInlineEnd: mobile ? "none" : "1px solid var(--dim)" }}
    >
      <div className="flex shrink-0 items-center justify-between px-4 py-3">
        <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--muted)" }}>
          {i18n("sections7ff5a6d")}
        </span>
        {!mobile ? (
          <button onClick={() => setLeftCollapsed(true)} className="text-xs" style={{ color: "var(--dim)" }}>
            &lt;
          </button>
        ) : null}
      </div>

      {/* Sections list — bounded when config is open, flex-1 when closed or during exercise drag */}
      <div
        ref={listRef}
        className="scroll-area flex flex-col gap-2 px-3 pb-3"
        style={{
          flex: sectionConfigOpen && selectedSection && !showAllSections ? "0 0 auto" : "1 1 0",
          maxHeight: sectionConfigOpen && selectedSection && !showAllSections ? "42%" : undefined,
          minHeight: "3.5rem",
        }}
      >
        <SortableContext items={sections.map((section) => section.localId)} strategy={verticalListSortingStrategy}>
          {sections.map((section) => (
            <SectionChip
              key={section.localId}
              section={section}
              isSelected={section.localId === selectedSectionId}
              onSelect={() => {
                if (section.localId === selectedSectionId) {
                  setSectionConfigOpen(!sectionConfigOpen);
                } else {
                  selectSection(section.localId);
                  if (onSectionSelected) onSectionSelected();
                }
              }}
            />
          ))}
        </SortableContext>

        <button
          onClick={addSection}
          className="rounded-2xl px-3 py-2 text-center text-sm font-semibold transition-colors"
          style={{
            border: "1px dashed var(--dim)",
            color: "var(--muted)",
          }}
        >
          {i18n("addSection416bc54")}
        </button>
      </div>

      {/* Section config — hidden during exercise drag so all section chips stay visible */}
      {sectionConfigOpen && selectedSection && !showAllSections ? (
        <div
          className="scroll-area border-t"
          style={{ flex: "1 1 0", height: 0, minHeight: "8rem", borderColor: "var(--dim)" }}
        >
          <SectionConfig section={selectedSection} />
        </div>
      ) : null}
    </div>
  );
}

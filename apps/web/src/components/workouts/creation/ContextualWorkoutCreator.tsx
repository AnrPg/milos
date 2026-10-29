"use client";

import { useState } from "react";

import { Dialog } from "@/components/ui/Dialog";
import { useUiTranslations } from "@/i18n/ui";

import { WorkoutAuthoringModes } from "./WorkoutAuthoringModes";

/**
 * «+ Νέο WOD» from inside another screen (a class form, a class's sheet, a
 * member's programming). The WOD editor opens over that screen instead of
 * replacing it, so the form underneath keeps everything the coach typed, and
 * publishing hands the new WOD straight back to it: `onPublished` assigns it
 * to the class, member or date the form is about, then the editor closes.
 *
 * `onPublished` may fail (e.g. the class was deleted meanwhile); its error is
 * shown by the screen underneath, where the assignment belongs, and the WOD
 * itself stays published in the library.
 */
export function ContextualWorkoutCreator({
  target,
  draftId = null,
  onPublished,
  onClose,
}: {
  /** What the new WOD is for, in plain words («CrossFit · Τρ 28/10 18:00»). */
  target?: string | null;
  /** Edit this draft (e.g. a copy made for one member) instead of a new WOD. */
  draftId?: string | null;
  onPublished: (workoutId: string) => void | Promise<void>;
  onClose: () => void;
}) {
  const i18n = useUiTranslations();
  const [assigning, setAssigning] = useState(false);

  async function published(workoutId: string) {
    setAssigning(true);
    try {
      await onPublished(workoutId);
    } finally {
      setAssigning(false);
      onClose();
    }
  }

  return (
    <Dialog
      onClose={onClose}
      // Escape belongs to the editor (menus, suggestions); leaving is the
      // explicit back button. The draft autosaves either way.
      dismissible={false}
      showClose={false}
      headerActions={
        <button
          type="button"
          className="rounded-full border px-3 py-1.5 text-sm font-semibold"
          style={{ borderColor: "var(--border)", color: "var(--text)" }}
          onClick={onClose}
          disabled={assigning}
        >
          {i18n("contextualWodBack")}
        </button>
      }
      size="full"
      variant="screen"
      panelClassName="sm:h-full"
      title={i18n("contextualWodTitle")}
      description={target ? i18n("contextualWodFor", { target }) : i18n("contextualWodHint")}
      plainBody
      testId="contextual-wod-creator"
    >
      <div className="min-h-0 flex-1 overflow-y-auto" aria-busy={assigning}>
        <WorkoutAuthoringModes embedded initialDraftId={draftId} onPublished={(id) => void published(id)} onCancel={onClose} />
      </div>
    </Dialog>
  );
}

"use client";

// Dev-only preview of the anatomy figure for the Playwright smoke test
// (e2e/anatomy-figure.spec.ts). `.dev.tsx` is a page extension in `next dev`
// only (next.config.ts), so this route does not exist in production builds.
import { useState } from "react";
import { useTranslations } from "next-intl";

import { AnatomyFigure } from "@/components/anatomy/AnatomyFigure";
import { AnatomyThumb } from "@/components/anatomy/AnatomyThumb";
import type { AnatomyHighlights, AnatomyPickLevel, AnatomyView } from "@/lib/anatomy/figure";

const FRAN: AnatomyHighlights = {
  quadriceps: "primary",
  glutes: "primary",
  "deltoid-anterior": "primary",
  "triceps-brachii": "primary",
  "latissimus-dorsi": "secondary",
  "biceps-brachii": "secondary",
  hamstrings: "secondary",
  "rectus-abdominis": "stabilizer",
  "erector-spinae": "stabilizer",
  "gluteus-medius": "felt",
};

const THUMB_SETS: AnatomyHighlights[] = [
  FRAN,
  { hamstrings: "primary", "erector-spinae": "primary", glutes: "secondary" },
  { "pectoralis-major": "primary", "triceps-brachii": "secondary", "deltoid-anterior": "secondary" },
  { "latissimus-dorsi": "primary", "biceps-brachii": "secondary", rhomboids: "stabilizer" },
];

const THUMB_VIEWS: AnatomyView[] = ["both", "front", "front"];

const FOCUS = ["glutes", "deltoid", "quadriceps", "latissimus-dorsi"];

export default function AnatomyPreviewPage() {
  const t = useTranslations("Anatomy");
  const [focus, setFocus] = useState<string | null>(null);
  const [view, setView] = useState<AnatomyView>("both");
  const [pick, setPick] = useState<{ nodeId: string; level: AnatomyPickLevel } | null>(null);

  return (
    <main className="mx-auto flex max-w-3xl flex-col gap-4 p-4">
      <div className="flex flex-wrap gap-2">
        {(["front", "back", "both"] as const).map((option) => (
          <button key={option} type="button" data-testid={`view-${option}`} onClick={() => setView(option)} className="rounded border px-2">
            {option}
          </button>
        ))}
        {FOCUS.map((id) => (
          <button key={id} type="button" data-testid={`focus-${id}`} onClick={() => setFocus(id)} className="rounded border px-2">
            {t(`muscle.${id}`)}
          </button>
        ))}
        <button type="button" data-testid="focus-none" onClick={() => setFocus(null)} className="rounded border px-2">
          ×
        </button>
      </div>
      <div data-testid="figure-wrap" className="w-full max-w-md">
        <AnatomyFigure
          highlights={FRAN}
          view={view}
          size="full"
          interactive
          focus={focus}
          onPick={(nodeId, level) => setPick({ nodeId, level })}
        />
      </div>
      <output data-testid="pick" data-node={pick?.nodeId ?? ""} data-level={pick?.level ?? ""}>
        {pick ? t(`muscle.${pick.nodeId}`) : null}
      </output>
      <div data-testid="thumbs" className="flex flex-wrap gap-2">
        {Array.from({ length: 24 }, (_, i) => (
          <AnatomyThumb key={i} highlights={THUMB_SETS[i % THUMB_SETS.length]} view={THUMB_VIEWS[i % THUMB_VIEWS.length]} />
        ))}
      </div>
    </main>
  );
}

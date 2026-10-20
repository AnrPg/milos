"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { hasCapability } from "@/components/client/entitlement";
import { JOURNAL_FEED_KEY } from "@/api/journal";
import { useClientEntitlement } from "@/components/client/use-client-entitlement";
import { NoteSheet } from "@/components/journal/NoteSheet";
import { localDate } from "@/components/member-app/wellness/wellness-model";
import { useWellness, wellnessWindow } from "@/components/member-app/wellness/WellnessPanel";
import { NewPRFormModal } from "@/components/pantheon/PRFormModal";
import { useSession } from "@/components/session-provider";
import { TrainingLogDialog, type TrainingLogDialogState } from "@/components/training-log/TrainingLog";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

/**
 * The kinds of entry a member can write today (brief §7.7), grouped as the
 * feature map groups them: Προπόνηση · Ευεξία · Coach · Σημείωση. Each kind
 * opens the flow that owns it. Νερό · Ύπνος · Γεύμα and Λιγούρα (ADR-159)
 * open Ευεξία; kinds still to come (Μέτρηση) join their group then, so the
 * sheet never shows a button that leads nowhere, and a group with no kinds
 * is not shown.
 */
export type NewEntryKind =
  | "workout"
  | "pr"
  | "wellness"
  | "craving"
  | "checkIn"
  | "injury"
  | "formReview"
  | "review"
  | "note";
export type NewEntryGroup = "training" | "wellbeing" | "coach" | "note";

export function newEntryGroups(options: {
  canRequestFormReview: boolean;
  /** False when the member turned water, sleep and meals all off in Ευεξία. */
  showWellness?: boolean;
}): { group: NewEntryGroup; kinds: NewEntryKind[] }[] {
  const wellness: NewEntryKind[] = options.showWellness === false ? [] : ["wellness"];
  const groups: { group: NewEntryGroup; kinds: NewEntryKind[] }[] = [
    { group: "training", kinds: ["workout", "pr"] },
    { group: "wellbeing", kinds: [...wellness, "checkIn", "craving", "injury"] },
    { group: "coach", kinds: [...(options.canRequestFormReview ? (["formReview"] as const) : []), "review"] },
    { group: "note", kinds: ["note"] },
  ];
  return groups.filter((entry) => entry.kinds.length > 0);
}

const ROUTES: Partial<Record<NewEntryKind, string>> = {
  wellness: "/journal/wellbeing#today",
  craving: "/journal/wellbeing?craving=new",
  checkIn: "/journal/wellbeing#check-in",
  injury: "/journal/wellbeing#report-injury",
  formReview: "/box/coach",
  review: "/journal/reviews#new-review",
};

export function NewEntryButton() {
  const t = useTranslations("MemberApp");
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl text-base font-bold"
        style={{ background: "var(--primary)", color: "var(--bg)" }}
      >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
          <path d="M4 20h4L19 9l-4-4L4 16v4Z" />
        </svg>
        {t("newEntry")}
      </button>
      {open ? <NewEntrySheet onClose={() => setOpen(false)} /> : null}
    </>
  );
}

function NewEntrySheet({ onClose }: { onClose: () => void }) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const { entitlement } = useClientEntitlement();
  const [flow, setFlow] = useState<"menu" | "pr" | "note" | TrainingLogDialogState>("menu");
  const today = localDate(new Date());
  const range = wellnessWindow(today, 0);
  const hidden = useWellness(range.from, range.to).data?.preferences?.hidden_items ?? [];
  const groups = newEntryGroups({
    canRequestFormReview: hasCapability(entitlement, "request_form_reviews"),
    showWellness: !(["water", "sleep", "meals"] as const).every((item) => hidden.includes(item)),
  });

  function choose(kind: NewEntryKind) {
    const route = ROUTES[kind];
    if (route) {
      onClose();
      router.push(route);
      return;
    }
    setFlow(kind === "pr" ? "pr" : kind === "note" ? "note" : { mode: "pick" });
  }

  if (flow === "pr") return <NewPRFormModal onClose={onClose} />;
  if (flow === "note")
    return (
      <NoteSheet
        onClose={onClose}
        onSaved={() => {
          void queryClient.invalidateQueries({ queryKey: JOURNAL_FEED_KEY });
          onClose();
        }}
      />
    );
  if (flow !== "menu") {
    if (flow.mode === "closed" || !tokens?.access_token) return null;
    return (
      <TrainingLogDialog
        state={flow}
        token={tokens.access_token}
        onNavigate={(next) => (next.mode === "closed" ? onClose() : setFlow(next))}
        onClose={onClose}
      />
    );
  }

  return <EntryMenu groups={groups} onChoose={choose} onClose={onClose} />;
}

function EntryMenu({
  groups,
  onChoose,
  onClose,
}: {
  groups: ReturnType<typeof newEntryGroups>;
  onChoose: (kind: NewEntryKind) => void;
  onClose: () => void;
}) {
  const t = useTranslations("MemberApp");
  const trapRef = useModalFocusTrap<HTMLDivElement>(onClose);
  return (
    <div
      className="fixed inset-0 z-[60] flex items-end justify-center sm:items-center"
      style={{ background: "rgba(0, 0, 0, 0.45)" }}
      onClick={onClose}
    >
      <div
        ref={trapRef}
        role="dialog"
        aria-modal="true"
        aria-label={t("newEntry")}
        className="w-full max-w-md rounded-t-3xl p-5 sm:rounded-3xl"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", paddingBottom: "calc(1.25rem + env(safe-area-inset-bottom))" }}
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="mb-4 text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("newEntry")}</h2>
        <div className="flex flex-col gap-4">
          {groups.map(({ group, kinds }) => (
            <section key={group} aria-labelledby={`entry-group-${group}`}>
              <h3
                id={`entry-group-${group}`}
                className="mb-2 text-xs font-semibold uppercase tracking-[0.18em]"
                style={{ color: "var(--dim)" }}
              >
                {t(`entryGroup.${group}`)}
              </h3>
              <ul className="grid grid-cols-2 gap-2">
                {kinds.map((kind) => (
                  <li key={kind}>
                    <button
                      type="button"
                      onClick={() => onChoose(kind)}
                      className="flex min-h-16 w-full flex-col items-start justify-center rounded-2xl px-4 py-3 text-start"
                      style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
                    >
                      <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t(`entryKind.${kind}`)}</span>
                      <span className="text-xs" style={{ color: "var(--dim)" }}>{t(`entryKindHint.${kind}`)}</span>
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
        <button
          type="button"
          onClick={onClose}
          className="mt-4 min-h-11 w-full rounded-2xl text-sm font-semibold"
          style={{ color: "var(--dim)", border: "1px solid var(--border)" }}
        >
          {t("cancel")}
        </button>
      </div>
    </div>
  );
}

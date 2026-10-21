"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  COACH_AUDIENCE_KEY,
  saveCoachAudience,
  setEntryAudience,
  setJournalVisibility,
  type AudienceKind,
  type ChoosableVisibility,
  type EntryAudience,
  type JournalFeedItem,
  type JournalMoveKind,
  type JournalVisibilityResult,
} from "@/api/journal";
import {
  audienceApplies,
  audienceAsked,
  AudienceChooser,
  isCoachRung,
  markAudienceAsked,
  useCoachAudience,
} from "@/components/journal/EntryAudience";
import { coachGroups, keysOf, refOf, sameKeys, within } from "@/lib/coach-audience";
import { orderedChoices, needsQuestion, VISIBILITY_ICON } from "@/components/journal/visibility";
import { useSession } from "@/components/session-provider";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

/**
 * The visibility badge every journal entry carries (vision §7.7, ADR-139).
 * Its rung and the rungs it may move to come from the server; tapping it
 * opens the picker when the entry can move at all. With more than one
 * provider, a coach rung also says whose coaches (ADR-162, board 17 Q5).
 */
type BadgeItem = Pick<JournalFeedItem, "id" | "journal_visibility" | "choosable_visibilities"> & {
  kind: JournalMoveKind;
  audience?: EntryAudience | null;
  /** Where the entry was recorded: its coaches always see it. */
  organization_id?: string | null;
};

export function VisibilityBadge({
  item,
  onChanged,
  onAudienceChanged,
}: {
  item: BadgeItem;
  onChanged?: (result: JournalVisibilityResult) => void;
  onAudienceChanged?: (audience: EntryAudience | null) => void;
}) {
  const t = useTranslations("MemberApp.journal");
  const [open, setOpen] = useState(false);
  const rung = item.journal_visibility;
  const choices = orderedChoices(item.choosable_visibilities);
  const movable = choices.some((choice) => choice !== rung) || needsQuestion(rung as ChoosableVisibility);
  const accent = rung === "coach_reply_requested";
  const label = (
    <>
      <span aria-hidden="true">{VISIBILITY_ICON[rung]}</span>
      {t(`visibility.${rung}`)}
    </>
  );
  const style = {
    background: accent ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "var(--panel-raised)",
    color: accent ? "var(--primary)" : "var(--dim)",
  };

  if (!movable) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold" style={style}>
        {label}
      </span>
    );
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={t("changeVisibility", { current: t(`visibility.${rung}`) })}
        className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold"
        style={style}
      >
        {label}
        <span aria-hidden="true">▾</span>
      </button>
      {open ? (
        <VisibilityPicker
          item={item}
          choices={choices}
          onClose={() => setOpen(false)}
          onChanged={(result, audience) => {
            setOpen(false);
            onChanged?.(result);
            if (audience !== undefined) onAudienceChanged?.(audience);
          }}
        />
      ) : null}
    </>
  );
}

function VisibilityPicker({
  item,
  choices,
  onClose,
  onChanged,
}: {
  item: Omit<BadgeItem, "choosable_visibilities">;
  choices: ChoosableVisibility[];
  onClose: () => void;
  /** `audience` is undefined when the entry's audience was not touched. */
  onChanged: (result: JournalVisibilityResult, audience?: EntryAudience | null) => void;
}) {
  const t = useTranslations("MemberApp.journal");
  const tApp = useTranslations("MemberApp");
  const { tokens } = useSession();
  const trapRef = useModalFocusTrap<HTMLDivElement>(onClose);
  const [choice, setChoice] = useState<ChoosableVisibility>(
    (choices as string[]).includes(item.journal_visibility)
      ? (item.journal_visibility as ChoosableVisibility)
      : choices[0],
  );
  const [question, setQuestion] = useState("");
  const queryClient = useQueryClient();
  const coachAudience = useCoachAudience();
  const home = item.organization_id ?? null;
  // The coaches this entry can be shared with: everyone but its own provider's.
  const groups = coachGroups(coachAudience.data, home);
  const defaultKeys = keysOf(coachAudience.data?.coaches);
  const defaults = within(defaultKeys, groups);
  const [picked, setPicked] = useState<string[] | null>(null);
  const [makeDefault, setMakeDefault] = useState<boolean | null>(() => (audienceAsked() ? null : true));
  const current = item.audience?.custom ? within(keysOf(item.audience.coaches), groups) : defaults;
  const selected = picked ?? (current.length > 0 ? current : defaults);
  const choosing =
    coachAudience.multiple && groups.length > 0 && audienceApplies(item.kind) && isCoachRung(choice);

  const mutation = useMutation({
    mutationFn: async () => {
      const token = tokens!.access_token;
      const result = await setJournalVisibility(token, item.kind, item.id, {
        visibility: choice,
        ...(needsQuestion(choice) ? { question: question.trim() } : {}),
      });
      if (!choosing || selected.length === 0) return { result, audience: undefined };
      markAudienceAsked();
      const kind = item.kind as AudienceKind;
      if (makeDefault) {
        if (!sameKeys(selected, defaults)) {
          // The home provider's coaches keep their place in the default.
          const keep = defaultKeys.filter((key) => !within([key], groups).length);
          await saveCoachAudience(token, [...keep, ...selected].map(refOf));
          void queryClient.invalidateQueries({ queryKey: COACH_AUDIENCE_KEY });
        }
        const audience = item.audience?.custom ? await setEntryAudience(token, kind, item.id, null) : undefined;
        return { result, audience };
      }
      if (!sameKeys(selected, defaults)) return { result, audience: await setEntryAudience(token, kind, item.id, selected.map(refOf)) };
      if (item.audience?.custom) return { result, audience: await setEntryAudience(token, kind, item.id, null) };
      return { result, audience: undefined };
    },
    onSuccess: ({ result, audience }) => onChanged(result, audience),
  });
  const blocked = !tokens?.access_token || (needsQuestion(choice) && question.trim() === "");
  const errorCode = mutation.error instanceof ApiError ? mutation.error.payload.code : null;

  return (
    <div
      className="fixed inset-0 z-[60] flex items-end justify-center sm:items-center"
      style={{ background: "var(--scrim)" }}
      onClick={onClose}
    >
      <div
        ref={trapRef}
        role="dialog"
        aria-modal="true"
        aria-label={t("whoSees")}
        className="w-full max-w-md rounded-t-3xl p-5 sm:rounded-3xl"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", paddingBottom: "calc(1.25rem + env(safe-area-inset-bottom))" }}
        onClick={(event) => event.stopPropagation()}
      >
        <VisibilityChoices
          choices={choices}
          value={choice}
          onChange={setChoice}
          question={question}
          onQuestionChange={setQuestion}
        />
        {choosing && coachAudience.data ? (
          <AudienceChooser
            audience={coachAudience.data}
            homeOrganizationId={home}
            selected={selected}
            onChange={setPicked}
            makeDefault={makeDefault}
            onMakeDefaultChange={setMakeDefault}
          />
        ) : null}
        {mutation.isError ? (
          <p role="alert" className="mt-3 text-sm font-semibold" style={{ color: "var(--danger)" }}>
            {errorCode === "no_active_coach" ? t("noCoach") : t("visibilityFailed")}
          </p>
        ) : null}
        <div className="mt-4 flex gap-2">
          <button
            type="button"
            onClick={onClose}
            className="min-h-11 flex-1 rounded-2xl text-sm font-semibold"
            style={{ color: "var(--dim)", border: "1px solid var(--border)" }}
          >
            {tApp("cancel")}
          </button>
          <button
            type="button"
            disabled={blocked || mutation.isPending}
            onClick={() => mutation.mutate()}
            className="min-h-11 flex-1 rounded-2xl text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {mutation.isPending ? t("saving") : needsQuestion(choice) ? t("askCoach") : t("save")}
          </button>
        </div>
      </div>
    </div>
  );
}

/** «Ποιος τη βλέπει»: the rungs as radio rows, with the question for a reply request. */
export function VisibilityChoices({
  choices,
  value,
  onChange,
  question,
  onQuestionChange,
}: {
  choices: ChoosableVisibility[];
  value: ChoosableVisibility;
  onChange: (rung: ChoosableVisibility) => void;
  question: string;
  onQuestionChange: (question: string) => void;
}) {
  const t = useTranslations("MemberApp.journal");
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="mb-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {t("whoSees")}
      </legend>
      {choices.map((rung) => (
        <label
          key={rung}
          className="flex cursor-pointer items-start gap-3 rounded-2xl px-3 py-2"
          style={{ background: value === rung ? "var(--panel-raised)" : "transparent", border: "1px solid var(--border)" }}
        >
          <input
            type="radio"
            name="journal-visibility"
            className="mt-1"
            checked={value === rung}
            onChange={() => onChange(rung)}
          />
          <span className="flex flex-col">
            <span className="text-sm font-bold" style={{ color: "var(--text)" }}>
              {VISIBILITY_ICON[rung]} {t(`visibility.${rung}`)}
            </span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t(`visibilityHint.${rung}`)}</span>
          </span>
        </label>
      ))}
      {choices.length === 1 && choices[0] === "private" ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("personalOnly")}</p>
      ) : null}
      {needsQuestion(value) ? (
        <label className="mt-1 flex flex-col gap-1">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("questionLabel")}</span>
          <textarea
            className="min-h-20 w-full resize-y rounded-xl px-3 py-2 text-sm outline-none"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            value={question}
            maxLength={5000}
            placeholder={t("questionPlaceholder")}
            onChange={(event) => onQuestionChange(event.target.value)}
          />
        </label>
      ) : null}
    </fieldset>
  );
}

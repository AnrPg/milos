"use client";

import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  createJournalNote,
  deleteJournalNote,
  NOTE_TOPICS,
  setJournalVisibility,
  updateJournalNote,
  type ChoosableVisibility,
  type JournalNote,
  type JournalNoteTopic,
} from "@/api/journal";
import { needsQuestion } from "@/components/journal/visibility";
import { VisibilityChoices } from "@/components/journal/VisibilityBadge";
import { PRGymField, prGymSlugForSubmit, usePRGymOptions } from "@/components/pantheon/PRGymField";
import { useSession } from "@/components/session-provider";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

const BODY_MAX = 4000;
const GYM_RUNGS: ChoosableVisibility[] = ["private", "coach_can_view", "coach_reply_requested"];

type Saved = { note: JournalNote; moveFailed: string | null };

/**
 * Σημείωση (ADR-140): a free-standing journal entry with a topic. A new one
 * picks its gym and who sees it in the same sheet; an existing one edits its
 * text here and moves on the ladder from its badge.
 */
export function NoteSheet({
  note,
  onClose,
  onSaved,
}: {
  note?: JournalNote;
  onClose: () => void;
  onSaved: () => void;
}) {
  const t = useTranslations("MemberApp.journal");
  const tApp = useTranslations("MemberApp");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const trapRef = useModalFocusTrap<HTMLDivElement>(onClose);
  const { gyms, defaultGymSlug } = usePRGymOptions();
  const [topic, setTopic] = useState<JournalNoteTopic>(note?.topic ?? "thought");
  const [body, setBody] = useState(note?.body ?? "");
  const [gymSlug, setGymSlug] = useState(defaultGymSlug);
  const [rung, setRung] = useState<ChoosableVisibility>("private");
  const [question, setQuestion] = useState("");
  const [moveError, setMoveError] = useState<string | null>(null);
  const personal = prGymSlugForSubmit(gymSlug) === null;
  const choices: ChoosableVisibility[] = personal ? ["private"] : GYM_RUNGS;
  const chosen = personal ? "private" : rung;

  const save = useMutation({
    mutationFn: async (): Promise<Saved> => {
      if (note) {
        const updated = await updateJournalNote(token!, note.id, {
          topic,
          body: body.trim(),
          lock_version: note.lock_version,
        });
        return { note: updated, moveFailed: null };
      }
      const created = await createJournalNote(token!, {
        topic,
        body: body.trim(),
        organization_slug: prGymSlugForSubmit(gymSlug),
        written_at: new Date().toISOString(),
        written_tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      });
      if (chosen === "private") return { note: created, moveFailed: null };
      try {
        await setJournalVisibility(token!, "note", created.id, {
          visibility: chosen,
          ...(needsQuestion(chosen) ? { question: question.trim() } : {}),
        });
        return { note: created, moveFailed: null };
      } catch (error) {
        const code = error instanceof ApiError ? error.payload.code : null;
        return { note: created, moveFailed: code === "no_active_coach" ? t("noCoach") : t("visibilityFailed") };
      }
    },
    onSuccess: ({ moveFailed }) => {
      // The note is saved either way; a failed move keeps the sheet open to say so.
      if (moveFailed) setMoveError(moveFailed);
      else onSaved();
    },
  });

  const remove = useMutation({
    mutationFn: () => deleteJournalNote(token!, note!.id),
    onSuccess: onSaved,
  });

  const busy = save.isPending || remove.isPending;
  const blocked =
    !token || body.trim() === "" || (!note && needsQuestion(chosen) && question.trim() === "") || Boolean(moveError);

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
        aria-label={note ? t("note.editTitle") : t("note.newTitle")}
        className="flex max-h-[90vh] w-full max-w-md flex-col gap-4 overflow-y-auto rounded-t-3xl p-5 sm:rounded-3xl"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", paddingBottom: "calc(1.25rem + env(safe-area-inset-bottom))" }}
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="text-lg font-bold" style={{ color: "var(--text)" }}>
          {note ? t("note.editTitle") : t("note.newTitle")}
        </h2>

        <div role="radiogroup" aria-label={t("note.topicLabel")} className="flex flex-wrap gap-2">
          {NOTE_TOPICS.map((option) => (
            <button
              key={option}
              type="button"
              role="radio"
              aria-checked={topic === option}
              onClick={() => setTopic(option)}
              className="rounded-full px-3 py-1.5 text-sm font-semibold"
              style={{
                background: topic === option ? "var(--primary)" : "var(--panel-raised)",
                color: topic === option ? "var(--primary-contrast)" : "var(--text)",
                border: "1px solid var(--border)",
              }}
            >
              {t(`noteTopic.${option}`)}
            </button>
          ))}
        </div>

        <label className="flex flex-col gap-1.5 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
          {t("note.bodyLabel")}
          <textarea
            value={body}
            onChange={(event) => setBody(event.target.value)}
            maxLength={BODY_MAX}
            rows={5}
            placeholder={t("note.bodyPlaceholder")}
            className="rounded-xl px-4 py-2.5 text-sm normal-case tracking-normal outline-none"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </label>

        {note ? null : (
          <>
            <PRGymField gyms={gyms} value={gymSlug} onChange={setGymSlug} />
            {personal ? (
              <p className="text-xs" style={{ color: "var(--dim)" }}>{t("personalOnly")}</p>
            ) : (
              <VisibilityChoices
                choices={choices}
                value={chosen}
                onChange={setRung}
                question={question}
                onQuestionChange={setQuestion}
              />
            )}
          </>
        )}

        {moveError ? (
          <p role="alert" className="text-sm font-semibold" style={{ color: "var(--danger)" }}>
            {t("note.savedPrivate", { reason: moveError })}
          </p>
        ) : save.isError || remove.isError ? (
          <p role="alert" className="text-sm font-semibold" style={{ color: "var(--danger)" }}>
            {t("note.saveFailed")}
          </p>
        ) : null}

        <div className="flex gap-2">
          {note ? (
            <button
              type="button"
              disabled={busy}
              onClick={() => remove.mutate()}
              className="min-h-11 rounded-2xl px-4 text-sm font-semibold disabled:opacity-50"
              style={{ color: "var(--danger)", border: "1px solid var(--border)" }}
            >
              {t("note.delete")}
            </button>
          ) : null}
          <button
            type="button"
            onClick={moveError ? onSaved : onClose}
            className="min-h-11 flex-1 rounded-2xl text-sm font-semibold"
            style={{ color: "var(--dim)", border: "1px solid var(--border)" }}
          >
            {moveError ? t("note.close") : tApp("cancel")}
          </button>
          {moveError ? null : (
            <button
              type="button"
              disabled={blocked || busy}
              onClick={() => save.mutate()}
              className="min-h-11 flex-1 rounded-2xl text-sm font-bold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {save.isPending ? t("saving") : !note && needsQuestion(chosen) ? t("askCoach") : t("save")}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

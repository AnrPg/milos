"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import {
  createCoachNote,
  deleteCoachNote,
  fetchCoachNoteReads,
  fetchCoachNotes,
  setNotesVisibility,
  updateCoachNote,
  type CoachNote,
  type CoachNoteSubject,
  type CoachNoteSubjectKind,
} from "@/api/roles";
import { notesAbout } from "@/components/admin/users/member-profile-tabs";
import { roleErrorKey } from "@/components/admin/staff-home";
import { formatDateTime } from "@/components/client/format";
import { useSession } from "@/components/session-provider";
import {
  dangerButtonStyle,
  inputClass,
  inputStyle,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  StatusText,
} from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can, membershipRoles } from "@/lib/role-navigation";

// Private coach notes on a client (ADR-101): coaches write their own; owners
// and admins may read them unless the coach turned that off, and every such
// read is logged for the coach to see.

/** A thing of the client's a note can be about, as the profile lists it. */
export type CoachNoteSubjectOption = CoachNoteSubject & { label: string };

const SUBJECT_KEYS: Record<CoachNoteSubjectKind, string> = {
  execution: "cnSubjectExecution",
  training_log: "cnSubjectTrainingLog",
  pr: "cnSubjectPr",
  injury: "cnSubjectInjury",
  form_review: "cnSubjectFormReview",
  assignment: "cnSubjectAssignment",
};

/**
 * ADR-140 §5: `kinds` shows the notes about those kinds of thing (a profile
 * tab); without it, every note and the privacy settings (Coaching › Coach
 * notes). `subjects` are what a new note here can be about.
 */
export function CoachNotesPanel({
  userId,
  kinds,
  subjects = [],
}: {
  userId: string;
  kinds?: CoachNoteSubjectKind[];
  subjects?: CoachNoteSubjectOption[];
}) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const { membership } = useSelectedMembershipRole();
  const canWrite = can(membership, "write_coach_notes");
  const isCoach = membershipRoles(membership).includes("coach");
  const notesKey = ["staff", "coach-notes", userId];

  const [draft, setDraft] = useState("");
  const [subjectKey, setSubjectKey] = useState("");
  const subjectFor = (key: string) => subjects.find((item) => `${item.kind}:${item.id}` === key) ?? null;
  const [editing, setEditing] = useState<{ id: string; body: string } | null>(null);

  const notes = useQuery({ queryKey: notesKey, enabled: Boolean(token), queryFn: () => fetchCoachNotes(token!, userId) });
  const reads = useQuery({
    queryKey: ["staff", "coach-notes", "reads"],
    enabled: Boolean(token) && isCoach,
    queryFn: () => fetchCoachNoteReads(token!),
  });
  const refresh = () => queryClient.invalidateQueries({ queryKey: notesKey });
  const create = useMutation({
    mutationFn: () => {
      const subject = subjectFor(subjectKey);
      return createCoachNote(token!, userId, draft.trim(), subject ? { kind: subject.kind, id: subject.id } : null);
    },
    onSuccess: async () => {
      setDraft("");
      setSubjectKey("");
      await refresh();
    },
  });
  const update = useMutation({
    mutationFn: (note: { id: string; body: string }) => updateCoachNote(token!, note.id, note.body.trim()),
    onSuccess: async () => {
      setEditing(null);
      await refresh();
    },
  });
  const remove = useMutation({ mutationFn: (id: string) => deleteCoachNote(token!, id), onSuccess: refresh });
  const visibility = useMutation({
    mutationFn: (visible: boolean) => setNotesVisibility(token!, visible),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["organization-memberships"] }),
  });

  const errorText = (error: unknown) => {
    const key = roleErrorKey(error);
    return key ? i18n(key) : localizeError(error, i18n);
  };
  const failed = [create, update, remove, visibility].find((mutation) => mutation.isError);
  const visibleToAdmins = visibility.isPending
    ? Boolean(visibility.variables)
    : (membership?.notes_visible_to_admins ?? true);
  const noteReads = (reads.data ?? []).filter((read) => read.client_user_id === userId);
  const own = (note: CoachNote) => note.coach_user_id === currentUser?.id;
  const shown = notesAbout(notes.data ?? [], kinds);
  const subjectLabel = (note: CoachNote) => {
    if (!note.subject_kind) return null;
    const known = subjects.find((item) => item.kind === note.subject_kind && item.id === note.subject_id);
    return known ? `${i18n(SUBJECT_KEYS[note.subject_kind])} · ${known.label}` : i18n(SUBJECT_KEYS[note.subject_kind]);
  };

  return (
    <div className="space-y-4">
      {notes.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : notes.isError ? (
        <StatusText tone="error">{errorText(notes.error)}</StatusText>
      ) : shown.length === 0 ? (
        <StatusText tone="muted">{i18n("rhNoCoachNotes")}</StatusText>
      ) : (
        <ul className="grid gap-2">
          {shown.map((note) => (
            <li key={note.id} className="rounded-[1.2rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
              <p className="text-xs" style={{ color: "var(--muted)" }}>
                {own(note) ? i18n("rhYou") : (note.coach_nickname ?? i18n("stfCoach"))}
                {note.inserted_at ? ` · ${formatDateTime(note.inserted_at, locale)}` : ""}
                {note.updated_at && note.inserted_at && note.updated_at !== note.inserted_at ? ` · ${i18n("rhEdited")}` : ""}
              </p>
              {subjectLabel(note) ? (
                <p className="mt-1 text-xs font-semibold" style={{ color: "var(--primary-strong)" }}>{subjectLabel(note)}</p>
              ) : null}
              {editing?.id === note.id ? (
                <form
                  className="mt-2 space-y-2"
                  onSubmit={(event) => {
                    event.preventDefault();
                    update.mutate(editing);
                  }}
                >
                  <textarea
                    aria-label={i18n("rhNoteBody")}
                    className={`${inputClass} min-h-20`}
                    style={inputStyle}
                    value={editing.body}
                    onChange={(event) => setEditing({ id: note.id, body: event.target.value })}
                  />
                  <div className="flex flex-wrap gap-2">
                    <button type="submit" disabled={update.isPending || !editing.body.trim()} className={secondaryButtonClass} style={primaryButtonStyle}>
                      {i18n("saveefc007a")}
                    </button>
                    <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setEditing(null)}>
                      {i18n("cancel77dfd21")}
                    </button>
                  </div>
                </form>
              ) : (
                <p className="mt-1 whitespace-pre-wrap" style={{ color: "var(--text)" }}>{note.body}</p>
              )}
              {own(note) && editing?.id !== note.id ? (
                <div className="mt-2 flex flex-wrap gap-2">
                  <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setEditing({ id: note.id, body: note.body })}>
                    {i18n("edit5301648")}
                  </button>
                  <button
                    type="button"
                    disabled={remove.isPending}
                    className={secondaryButtonClass}
                    style={dangerButtonStyle}
                    onClick={() => {
                      if (window.confirm(i18n("rhDeleteNoteConfirm"))) remove.mutate(note.id);
                    }}
                  >
                    {i18n("deletef6fdbe4")}
                  </button>
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}

      {canWrite && (!kinds || subjects.length > 0) ? (
        <form
          className="space-y-2"
          onSubmit={(event) => {
            event.preventDefault();
            create.mutate();
          }}
        >
          <textarea
            aria-label={i18n("rhNewNote")}
            placeholder={i18n("rhNewNotePlaceholder")}
            className={`${inputClass} min-h-20`}
            style={inputStyle}
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
          />
          {subjects.length > 0 ? (
            <label className="block text-xs" style={{ color: "var(--dim)" }}>
              {i18n("cnAbout")}
              <select
                className={`${inputClass} mt-1`}
                style={inputStyle}
                value={subjectKey}
                onChange={(event) => setSubjectKey(event.target.value)}
              >
                <option value="">{kinds ? i18n("cnAboutPick") : i18n("cnAboutNothing")}</option>
                {subjects.map((item) => (
                  <option key={`${item.kind}:${item.id}`} value={`${item.kind}:${item.id}`}>
                    {i18n(SUBJECT_KEYS[item.kind])} · {item.label}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          <button
            type="submit"
            disabled={create.isPending || !draft.trim() || (Boolean(kinds) && !subjectKey)}
            className={primaryButtonClass}
            style={primaryButtonStyle}
          >
            {create.isPending ? i18n("loading33ce417") : i18n("rhAddNote")}
          </button>
        </form>
      ) : null}

      {failed ? <StatusText tone="error">{errorText(failed.error)}</StatusText> : null}

      {isCoach && canWrite && !kinds ? (
        <details className="rounded-[1.2rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <summary className="cursor-pointer font-semibold" style={{ color: "var(--text)" }}>{i18n("rhNotePrivacy")}</summary>
          <label className="mt-3 flex items-start gap-3">
            <input
              type="checkbox"
              className="mt-1"
              checked={visibleToAdmins}
              disabled={visibility.isPending}
              onChange={(event) => visibility.mutate(event.target.checked)}
            />
            <span>
              <span className="block font-semibold" style={{ color: "var(--text)" }}>{i18n("rhAdminsMayRead")}</span>
              <span className="block text-xs" style={{ color: "var(--dim)" }}>{i18n("rhAdminsMayReadHelp")}</span>
            </span>
          </label>
          <p className="mt-4 text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{i18n("rhReadLog")}</p>
          {reads.isPending ? (
            <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
          ) : reads.isError ? (
            <StatusText tone="error">{errorText(reads.error)}</StatusText>
          ) : noteReads.length === 0 ? (
            <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{i18n("rhNoReads")}</p>
          ) : (
            <ul className="mt-2 space-y-1 text-xs">
              {noteReads.map((read) => {
                const note = (notes.data ?? []).find((item) => item.id === read.note_id);
                return (
                  <li key={read.id} style={{ color: "var(--text-soft)" }}>
                    {i18n("rhReadBy", {
                      reader: read.reader_nickname ?? i18n("rhAnAdmin"),
                      time: formatDateTime(read.read_at, locale),
                    })}
                    {note ? <span style={{ color: "var(--dim)" }}> · “{note.body.slice(0, 40)}{note.body.length > 40 ? "…" : ""}”</span> : null}
                  </li>
                );
              })}
            </ul>
          )}
        </details>
      ) : null}
    </div>
  );
}

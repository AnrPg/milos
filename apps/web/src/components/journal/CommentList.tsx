"use client";

import { useFormatter, useTranslations } from "next-intl";

import type { JournalComment } from "@/api/journal-comments";
import { SemanticLabel } from "@/components/semantic-label";
import { changeSummary } from "@/lib/journal-comments";

/**
 * One list of Σχόλια (ADR-140 §1), oldest first, the same wherever the entry
 * is shown: what each refers to, the change it records, its tags and text.
 */
export function CommentList({
  comments,
  anchorLabel,
  emptyText,
  pendingIds = [],
  onEdit,
  onDelete,
}: {
  comments: JournalComment[];
  /** A readable name for an exercise or row id, when the surface knows one. */
  anchorLabel?: (comment: JournalComment) => string | null;
  emptyText?: string;
  /** Saved on this device but not yet on the server. */
  pendingIds?: string[];
  onEdit?: (comment: JournalComment) => void;
  onDelete?: (comment: JournalComment) => void;
}) {
  const t = useTranslations("MemberApp.comments");
  const format = useFormatter();

  if (comments.length === 0) {
    return emptyText ? (
      <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
        {emptyText}
      </p>
    ) : null;
  }

  return (
    <ul className="space-y-2">
      {comments.map((comment) => {
        const anchor =
          anchorLabel?.(comment) ??
          comment.change?.exercise_name ??
          comment.selected_text ??
          comment.change?.section_name ??
          null;
        return (
          <li
            key={comment.id}
            className="rounded-2xl px-3 py-2 text-sm"
            style={{
              background: comment.change
                ? "color-mix(in srgb, var(--warning) 10%, transparent)"
                : "color-mix(in srgb, var(--primary) 8%, transparent)",
              borderInlineStart: `4px solid color-mix(in srgb, ${comment.change ? "var(--warning)" : "var(--primary)"} 50%, transparent)`,
            }}
          >
            <div className="flex items-baseline justify-between gap-2">
              <p className="font-semibold" style={{ color: "var(--text)" }}>
                {anchor ?? t("wholeEntry")}
              </p>
              <span className="shrink-0 text-xs" style={{ color: "var(--dim)" }}>
                {pendingIds.includes(comment.id)
                  ? t("pending")
                  : format.dateTime(new Date(comment.written_at), { dateStyle: "short", timeStyle: "short" })}
              </span>
            </div>
            {comment.change ? (
              <p className="mt-0.5" style={{ color: "var(--muted)" }}>
                <SemanticLabel value={comment.change.field} />
                {": "}
                <bdi>{changeSummary(comment.change)}</bdi>
                {comment.change.set_index ? ` · ${t("set", { set: comment.change.set_index })}` : ""}
              </p>
            ) : null}
            {comment.tags.length > 0 ? (
              <p className="mt-1 flex flex-wrap gap-1">
                {comment.tags.map((tag) => (
                  <span
                    key={tag}
                    className="rounded-lg px-2 py-0.5 text-xs font-semibold"
                    style={{ background: "var(--panel-raised)", color: "var(--muted)" }}
                  >
                    {tag}
                  </span>
                ))}
              </p>
            ) : null}
            {comment.body ? (
              <p className="mt-1 whitespace-pre-wrap break-words" style={{ color: "var(--text)" }}>
                {comment.body}
              </p>
            ) : null}
            {onEdit || onDelete ? (
              <div className="mt-1 flex gap-3 text-xs font-semibold">
                {onEdit ? (
                  <button type="button" onClick={() => onEdit(comment)} style={{ color: "var(--primary-strong, var(--primary))" }}>
                    {t("edit")}
                  </button>
                ) : null}
                {onDelete ? (
                  <button type="button" onClick={() => onDelete(comment)} style={{ color: "var(--danger)" }}>
                    {t("delete")}
                  </button>
                ) : null}
              </div>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

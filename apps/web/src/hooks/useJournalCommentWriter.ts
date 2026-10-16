"use client";

import { useCallback, useMemo } from "react";

import type { JournalComment, JournalCommentDraft } from "@/api/journal-comments";
import { useSession } from "@/components/session-provider";
import { useOutboxCommand } from "@/hooks/useOutboxCommand";
import type { JournalCommentDeletePayload } from "@/lib/offline-command-adapters";
import { localComment } from "@/lib/journal-comments";

export type SavedComment = { comment: JournalComment; synced: boolean };

/**
 * Writes Σχόλια (ADR-140 §1) through the device outbox, so a comment written
 * offline (mid-workout in a basement gym) is kept and sent later. A save
 * answers with the server's comment, or with a local copy while it waits.
 */
export function useJournalCommentWriter() {
  const submit = useOutboxCommand();
  const { currentUser } = useSession();
  const userId = currentUser?.id ?? null;

  const save = useCallback(
    async (draft: JournalCommentDraft): Promise<SavedComment> => {
      const result = await submit<JournalComment, JournalCommentDraft>("journal_comment.save", draft);
      return result.status === "delivered"
        ? { comment: result.result, synced: true }
        : { comment: localComment(draft, userId), synced: false };
    },
    [submit, userId],
  );

  const remove = useCallback(
    async (id: string): Promise<void> => {
      await submit<void, JournalCommentDeletePayload>("journal_comment.delete", { id });
    },
    [submit],
  );

  return useMemo(() => ({ save, remove }), [save, remove]);
}

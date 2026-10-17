import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Σχόλια (ADR-140 §1): text a member writes on their own execution,
 * training-log entry or PR, from any surface. Saves are idempotent upserts
 * by the client-generated id; a structured change is also upserted by its
 * patch id, so the server may answer with an existing comment's id.
 */
export type JournalComment = components["schemas"]["JournalComment"];
export type JournalCommentChange = components["schemas"]["JournalCommentChange"];
export type JournalCommentInput = components["schemas"]["JournalCommentInput"];
export type JournalCommentSave = components["schemas"]["JournalCommentSave"];
export type JournalEntryKind = JournalComment["entry_kind"];

export type JournalCommentDraft = JournalCommentSave & { id: string };

export function newCommentId(): string {
  return crypto.randomUUID();
}

export async function saveJournalComment(
  token: string,
  { id, ...body }: JournalCommentDraft,
): Promise<JournalComment> {
  const data = await apiRequest<{ comment: JournalComment }>(`/journal/comments/${id}`, {
    method: "PUT",
    token,
    body,
  });
  return data.comment;
}

export async function saveJournalComments(
  token: string,
  comments: JournalCommentDraft[],
): Promise<JournalComment[]> {
  if (comments.length === 0) return [];
  const data = await apiRequest<{ comments: JournalComment[] }>("/journal/comments/batch", {
    method: "POST",
    token,
    body: { comments },
  });
  return data.comments;
}

export async function deleteJournalComment(token: string, id: string): Promise<void> {
  await apiRequest<void>(`/journal/comments/${id}`, { method: "DELETE", token });
}

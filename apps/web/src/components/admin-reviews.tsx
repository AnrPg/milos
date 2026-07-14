"use client";

import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";

import { fetchAdminReviews, updateReviewStatus } from "@/api/reviews";
import { useSession } from "@/components/session-provider";

type ReviewAnswer = {
  question_key?: unknown;
  question_text?: unknown;
  answer_text?: unknown;
  rating_value?: unknown;
};

export function AdminReviews() {
  const { tokens } = useSession();
  const [offset, setOffset] = useState(0);
  const [tagDrafts, setTagDrafts] = useState<Record<string, string>>({});
  const pageSize = 25;

  const reviewsQuery = useQuery({
    queryKey: ["admin", "reviews", offset],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () =>
      fetchAdminReviews(tokens!.access_token, { limit: String(pageSize), offset: String(offset) }),
  });

  const statusMutation = useMutation({
    mutationFn: async ({ id, status, tags }: { id: string; status: string; tags?: string[] }) =>
      updateReviewStatus(tokens!.access_token, id, { status, tags }),
    onSuccess: () => reviewsQuery.refetch(),
  });

  const reviews = reviewsQuery.data?.reviews ?? [];

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-5xl space-y-6">
        <section className="rounded-[2rem] border border-[color:var(--border)] bg-[var(--panel)] p-8">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">Feedback admin</p>
          <h1 className="mt-3 text-4xl font-black">Reviews and satisfaction signals</h1>
          <p className="mt-3 text-sm leading-6 text-[var(--muted)]">
            MVP moderation view for workout, exercise, gym, and coaching reviews. Analytics will consume the same
            persisted records.
          </p>
        </section>

        <section className="grid gap-4">
          {reviews.length === 0 ? <p className="rounded-2xl bg-[var(--panel)]/5 p-5 text-sm">No reviews yet.</p> : null}
          {reviews.map((review) => {
            const answers = Array.isArray(review.answers) ? (review.answers as ReviewAnswer[]) : [];
            const reviewId = String(review.id);
            const snapshot = review.target_snapshot && typeof review.target_snapshot === "object"
              ? (review.target_snapshot as Record<string, unknown>)
              : {};
            const tags = Array.isArray(review.tags) ? review.tags.map(String) : [];
            const tagDraft = tagDrafts[reviewId] ?? tags.join(", ");

            return (
              <article key={reviewId} className="rounded-[1.5rem] border border-[color:var(--border)] bg-[var(--panel)] p-5">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="font-bold">
                      {String(snapshot.label ?? review.target_type)}
                    </p>
                    <p className="text-sm text-[var(--muted)]">
                      {String(review.target_type)} · Rating {String(review.rating ?? "n/a")} · {String(review.sentiment)} · {String(review.status)}
                    </p>
                    {review.target_id ? (
                      <p className="mt-1 text-xs text-[var(--dim)]">Target {String(review.target_id)}</p>
                    ) : null}
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <button
                      className="rounded-full bg-[var(--primary)] px-4 py-2 text-sm font-bold text-[var(--bg)]"
                      type="button"
                      onClick={() => statusMutation.mutate({ id: reviewId, status: "reviewed", tags: splitTags(tagDraft) })}
                    >
                      Mark reviewed
                    </button>
                    <button
                      className="rounded-full border border-[var(--primary)] px-4 py-2 text-sm font-bold text-[var(--primary)]"
                      type="button"
                      onClick={() => statusMutation.mutate({ id: reviewId, status: "needs_follow_up", tags: splitTags(tagDraft) })}
                    >
                      Needs follow-up
                    </button>
                  </div>
                </div>
                <input
                  className="mt-4 w-full rounded-xl border border-[color:var(--border)] bg-[var(--bg)] px-3 py-2 text-sm text-[var(--text)] outline-none"
                  placeholder="triage tags"
                  value={tagDraft}
                  onChange={(event) => setTagDrafts({ ...tagDrafts, [reviewId]: event.target.value })}
                />
                {review.body ? <p className="mt-3 text-sm leading-6 text-[var(--text)]">{String(review.body)}</p> : null}
                {answers.length > 0 ? (
                  <div className="mt-4 grid gap-3">
                    {answers.map((answer, index) => (
                      <div
                        key={`${String(review.id)}-${index}`}
                        className="rounded-[1rem] border border-[color:var(--border)] bg-[var(--bg)] p-4"
                      >
                        <p className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--primary)]">
                          {String(answer.question_key ?? `answer_${index + 1}`)}
                        </p>
                        <p className="mt-2 text-sm font-semibold text-[var(--text)]">
                          {String(answer.question_text ?? "Question")}
                        </p>
                        <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                          {String(answer.answer_text ?? "")}
                          {answer.rating_value ? ` · ${String(answer.rating_value)}/5` : ""}
                        </p>
                      </div>
                    ))}
                  </div>
                ) : null}
              </article>
            );
          })}
        </section>
        <div className="flex items-center justify-between">
          <button
            className="rounded-full border border-[color:var(--border)] px-4 py-2 text-sm font-bold disabled:opacity-40"
            disabled={offset === 0}
            type="button"
            onClick={() => setOffset(Math.max(offset - pageSize, 0))}
          >
            Previous
          </button>
          <button
            className="rounded-full border border-[color:var(--border)] px-4 py-2 text-sm font-bold disabled:opacity-40"
            disabled={reviews.length < pageSize}
            type="button"
            onClick={() => setOffset(offset + pageSize)}
          >
            Next
          </button>
        </div>
      </div>
    </main>
  );
}

function splitTags(value: string) {
  return value
    .split(",")
    .map((tag) => tag.trim())
    .filter(Boolean);
}

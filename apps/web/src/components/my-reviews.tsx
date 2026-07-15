"use client";

import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";

import { listMyExecutions, type WorkoutExecution } from "@/api/executions";
import { fetchMyReviews, submitReview } from "@/api/reviews";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";

export function recentWorkoutTargets(executions: WorkoutExecution[]) {
  const byWorkout = new Map<string, { id: string; label: string }>();

  executions.forEach((execution) => {
    if (!execution.master_workout_id || byWorkout.has(execution.master_workout_id)) return;

    byWorkout.set(execution.master_workout_id, {
      id: execution.master_workout_id,
      label:
        execution.workout_title ??
        `${execution.workout_type ?? "Workout"} · ${String(execution.started_at_utc).slice(0, 10)}`,
    });
  });

  return Array.from(byWorkout.values()).slice(0, 20);
}

export function isCompletedExecution(execution: WorkoutExecution) {
  return execution.status === "completed" || Boolean(execution.completed_at_utc);
}

function ErrorText({ error }: { error: unknown }) {
  if (!(error instanceof Error)) return null;
  return <p className="text-sm font-semibold text-[var(--danger)]">{error.message}</p>;
}

const QUESTIONS = [
  { key: "ability_match", text: "How well did this workout match your current ability today?" },
  { key: "useful_part", text: "Which part felt most useful or enjoyable?" },
  { key: "hard_part", text: "Which part felt too hard, painful, confusing, or unnecessary?" },
  { key: "next_adjustment", text: "What should your coach adjust next time?" },
];

export function ReviewForm() {
  const { tokens } = useSession();
  const [targetType, setTargetType] = useState("workout");
  const [targetId, setTargetId] = useState("");
  const [rating, setRating] = useState("5");
  const [answers, setAnswers] = useState<Record<string, string>>({
    ability_match: "",
    useful_part: "",
    hard_part: "",
    next_adjustment: "",
  });

  const targetRequiresId = ["workout", "exercise", "execution", "class_slot", "membership_package"].includes(targetType);

  const executionsQuery = useQuery({
    queryKey: ["my", "executions", "review-targets"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => listMyExecutions(tokens!.access_token),
  });

  const executions = executionsQuery.data ?? [];
  const completedExecutions = executions.filter(isCompletedExecution);
  const workoutTargets = recentWorkoutTargets(completedExecutions);
  const executionTargets = completedExecutions.slice(0, 20);
  const defaultTargetId =
    targetType === "workout"
      ? workoutTargets[0]?.id
      : targetType === "execution"
        ? executionTargets[0]?.id
        : "";
  const selectedTargetId = targetId || defaultTargetId || "";

  const submitMutation = useMutation({
    mutationFn: async () =>
      submitReview(tokens!.access_token, {
        target_type: targetType,
        ...(targetRequiresId ? { target_id: selectedTargetId.trim() } : {}),
        rating: Number(rating),
        sentiment: Number(rating) >= 4 ? "positive" : Number(rating) <= 2 ? "negative" : "neutral",
        body: QUESTIONS.map((q) => answers[q.key].trim())
          .filter(Boolean)
          .join("\n\n"),
        answers: QUESTIONS.map((q) => ({
          question_key: q.key,
          question_text: q.text,
          answer_text: answers[q.key].trim(),
          rating_value: q.key === "ability_match" ? Number(rating) : undefined,
        })),
      }),
    onSuccess: () => {
      setAnswers({ ability_match: "", useful_part: "", hard_part: "", next_adjustment: "" });
      setTargetId("");
    },
  });

  return (
    <form
      className="space-y-4 rounded-[1.6rem] border border-[var(--border)] bg-[var(--panel)] p-6"
      onSubmit={(event) => {
        event.preventDefault();
        submitMutation.mutate();
      }}
    >
      <div className="grid gap-3 md:grid-cols-2">
        <select
          className="rounded-2xl border px-4 py-3"
          value={targetType}
          onChange={(event) => {
            setTargetType(event.target.value);
            setTargetId("");
          }}
        >
          <option value="workout">Workout</option>
          <option value="execution">Execution</option>
          <option value="gym_parameter">Gym parameter</option>
          <option value="coaching_parameter">Private coaching</option>
          <option value="exercise">Exercise</option>
          <option value="class_slot">Class slot</option>
          <option value="membership_package">Membership package</option>
          <option value="general">General</option>
        </select>
        <input
          className="rounded-2xl border px-4 py-3"
          max={5}
          min={1}
          type="number"
          value={rating}
          onChange={(event) => setRating(event.target.value)}
        />
      </div>
      {targetType === "workout" && workoutTargets.length > 0 ? (
        <select
          className="w-full rounded-2xl border px-4 py-3"
          required
          value={selectedTargetId}
          onChange={(event) => setTargetId(event.target.value)}
        >
          {workoutTargets.map((workout) => (
            <option key={workout.id} value={workout.id}>
              {workout.label}
            </option>
          ))}
        </select>
      ) : null}
      {targetType === "execution" && executionTargets.length > 0 ? (
        <select
          className="w-full rounded-2xl border px-4 py-3"
          required
          value={selectedTargetId}
          onChange={(event) => setTargetId(event.target.value)}
        >
          {executionTargets.map((execution) => (
            <option key={execution.id} value={execution.id}>
              {execution.workout_title ?? execution.master_workout_id ?? execution.id} ·{" "}
              {String(execution.status)}
            </option>
          ))}
        </select>
      ) : null}
      {targetRequiresId && !["workout", "execution"].includes(targetType) ? (
        <input
          className="w-full rounded-2xl border px-4 py-3"
          placeholder="Target ID"
          required
          value={targetId}
          onChange={(event) => setTargetId(event.target.value)}
        />
      ) : null}
      <div className="grid gap-3">
        {QUESTIONS.map((question) => (
          <label key={question.key}>
            <span className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--muted)]">
              {question.text}
            </span>
            <textarea
              className="mt-2 min-h-24 w-full rounded-2xl border px-4 py-3"
              value={answers[question.key]}
              onChange={(event) => setAnswers({ ...answers, [question.key]: event.target.value })}
            />
          </label>
        ))}
      </div>
      <button
        className="rounded-full bg-[var(--text)] px-5 py-3 text-sm font-bold text-[var(--primary-contrast)] disabled:opacity-50"
        disabled={submitMutation.isPending || (targetRequiresId && !selectedTargetId.trim())}
        type="submit"
      >
        {submitMutation.isPending ? "Submitting..." : "Submit review"}
      </button>
      <ErrorText error={submitMutation.error} />
    </form>
  );
}

type Review = {
  id: unknown;
  target_type: unknown;
  rating?: unknown;
  body?: unknown;
};

export function ReviewList({ reviews }: { reviews: Review[] }) {
  if (reviews.length === 0) {
    return (
      <p className="text-sm" style={{ color: "var(--muted)" }}>
        No reviews submitted yet.
      </p>
    );
  }

  return (
    <section className="grid gap-3">
      {reviews.map((review) => (
        <article
          key={String(review.id)}
          className="rounded-2xl border border-[var(--border)] bg-[var(--panel)] p-5"
        >
          <p className="font-bold">{String(review.target_type)}</p>
          <p className="text-sm text-[var(--muted)]">Rating {String(review.rating ?? "n/a")}</p>
          {review.body ? <p className="mt-2 text-sm">{String(review.body)}</p> : null}
        </article>
      ))}
    </section>
  );
}

export function MyReviews() {
  const { tokens } = useSession();

  const reviewsQuery = useQuery({
    queryKey: ["my", "reviews"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchMyReviews(tokens!.access_token),
  });

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-4xl space-y-6">
        <TransientHero label="reviews introduction">
        <section className="rounded-[2rem] border border-[var(--border)] bg-[var(--panel)] p-5">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">
            My reviews
          </p>
          <h1 className="mt-2 text-3xl font-black">Leave feedback without losing history.</h1>
        </section>
        </TransientHero>

        <ReviewForm />

        <ReviewList reviews={(reviewsQuery.data?.reviews ?? []) as Review[]} />
      </div>
    </main>
  );
}

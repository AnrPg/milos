"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useState } from "react";

import { completeFormReview, fetchFormReviewQueue, type FormReview, type FormReviewStatus } from "@/api/staff";
import { useSession } from "@/components/session-provider";
import { staffErrorMessage } from "@/components/staff/staff-helpers";
import {
  inputClass,
  inputStyle,
  captionClass,
  captionStyle,
  Pill,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  StaffPanel,
  StatusText,
} from "@/components/staff/staff-ui";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

const QUEUE_KEY = ["staff", "form-reviews"] as const;

function ReviewForm({ review, onDone }: { review: FormReview; onDone: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const fieldId = useId();
  const [feedback, setFeedback] = useState("");

  const mutation = useMutation({
    mutationFn: () => completeFormReview(tokens!.access_token, review.id, feedback.trim()),
    onSuccess: async () => {
      setFeedback("");
      await queryClient.invalidateQueries({ queryKey: QUEUE_KEY });
      onDone();
    },
  });

  return (
    <form
      className="mt-3 space-y-2"
      onSubmit={(event) => {
        event.preventDefault();
        if (feedback.trim().length >= 2) mutation.mutate();
      }}
    >
      <label className={captionClass} htmlFor={fieldId} style={captionStyle}>
        {i18n("stfFeedbackLabel")}
      </label>
      <textarea
        id={fieldId}
        className={`${inputClass} min-h-28`}
        maxLength={5000}
        onChange={(event) => setFeedback(event.target.value)}
        placeholder={i18n("stfFeedbackPlaceholder")}
        style={inputStyle}
        value={feedback}
      />
      <div className="flex flex-wrap items-center gap-3">
        <button
          className={primaryButtonClass}
          disabled={feedback.trim().length < 2 || mutation.isPending}
          style={primaryButtonStyle}
          type="submit"
        >
          {mutation.isPending ? i18n("stfSending") : i18n("stfSendFeedback")}
        </button>
        <button className={secondaryButtonClass} onClick={onDone} style={secondaryButtonStyle} type="button">
          {i18n("cancel77dfd21")}
        </button>
      </div>
      {mutation.isError ? <StatusText tone="error">{staffErrorMessage(mutation.error, i18n)}</StatusText> : null}
    </form>
  );
}

export function FormReviewQueue() {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens } = useSession();
  const [status, setStatus] = useState<FormReviewStatus>("submitted");
  const [openId, setOpenId] = useState<string | null>(null);
  const filterId = useId();

  const query = useQuery({
    queryKey: [...QUEUE_KEY, status],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchFormReviewQueue(tokens!.access_token, status),
  });

  const reviews = query.data ?? [];
  const when = (iso: string | null | undefined) =>
    iso ? new Intl.DateTimeFormat(uiLocale, { dateStyle: "medium", timeStyle: "short" }).format(new Date(iso)) : "—";

  return (
    <StaffPanel
      eyebrow={i18n("stfFormReviewsEyebrow")}
      labelledBy="staff-form-reviews"
      title={i18n("stfFormReviewsTitle")}
      actions={
        <div className="flex items-center gap-2">
          <label className="sr-only" htmlFor={filterId}>
            {i18n("statusbae7d5b")}
          </label>
          <select
            id={filterId}
            className="rounded-xl px-3 py-1.5 text-sm"
            onChange={(event) => setStatus(event.target.value as FormReviewStatus)}
            style={inputStyle}
            value={status}
          >
            <option value="submitted">{i18n("stfReviewStatusSubmitted")}</option>
            <option value="reviewed">{i18n("stfReviewStatusReviewed")}</option>
            <option value="withdrawn">{i18n("stfReviewStatusWithdrawn")}</option>
          </select>
        </div>
      }
    >
      {query.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : query.isError ? (
        <StatusText tone="error">{staffErrorMessage(query.error, i18n)}</StatusText>
      ) : reviews.length === 0 ? (
        <StatusText tone="muted">
          {status === "submitted" ? i18n("stfNoOpenFormReviews") : i18n("stfNoFormReviews")}
        </StatusText>
      ) : (
        <ul className="space-y-3">
          {reviews.map((review) => (
            <li
              key={review.id}
              className="rounded-[1.4rem] p-4"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {review.nickname ?? i18n("stfUnknownMember")}
                    {review.exercise_name ? (
                      <span style={{ color: "var(--muted)" }}> · {review.exercise_name}</span>
                    ) : null}
                  </p>
                  <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
                    {i18n("stfSubmittedAt", { time: when(review.inserted_at) })}
                  </p>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  {review.status === "submitted" ? (
                    <Pill tone="primary">{i18n("stfReviewStatusSubmitted")}</Pill>
                  ) : review.status === "reviewed" ? (
                    <Pill tone="success">{i18n("stfReviewStatusReviewed")}</Pill>
                  ) : (
                    <Pill tone="neutral">{i18n("stfReviewStatusWithdrawn")}</Pill>
                  )}
                  <a
                    className={secondaryButtonClass}
                    href={review.video_url}
                    rel="noopener noreferrer"
                    style={secondaryButtonStyle}
                    target="_blank"
                  >
                    {i18n("stfOpenVideo")}
                  </a>
                </div>
              </div>
              {review.note ? (
                <p
                  className="mt-3 whitespace-pre-wrap break-words text-sm leading-6"
                  data-user-text
                  style={{ color: "var(--text-soft)" }}
                >
                  {review.note}
                </p>
              ) : null}
              {review.feedback ? (
                <div className="mt-3 rounded-[1rem] p-3" style={{ background: "var(--panel)" }}>
                  <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("stfFeedbackLabel")}
                    {review.reviewed_at ? ` · ${when(review.reviewed_at)}` : ""}
                  </p>
                  <p className="mt-1 whitespace-pre-wrap break-words text-sm" data-user-text style={{ color: "var(--text)" }}>
                    {review.feedback}
                  </p>
                </div>
              ) : null}
              {review.status === "submitted" ? (
                openId === review.id ? (
                  <ReviewForm review={review} onDone={() => setOpenId(null)} />
                ) : (
                  <button
                    className={`${primaryButtonClass} mt-3`}
                    onClick={() => setOpenId(review.id)}
                    style={primaryButtonStyle}
                    type="button"
                  >
                    {i18n("stfWriteReview")}
                  </button>
                )
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </StaffPanel>
  );
}

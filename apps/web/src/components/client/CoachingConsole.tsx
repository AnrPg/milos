"use client";

import { useId, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  fetchMyFormReviews,
  fetchMyNutritionPlan,
  submitFormReview,
  withdrawFormReview,
  type FormReview,
} from "@/api/coaching-extras";
import { useSession } from "@/components/session-provider";
import { ClientCard, ClientPage, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { allowanceRemaining, hasCapability, responseSlaHours } from "@/components/client/entitlement";
import { clientErrorMessage } from "@/components/client/errors";
import { FeatureGate } from "@/components/client/FeatureGate";
import { formatDateTime } from "@/components/client/format";
import { CLIENT_ENTITLEMENT_QUERY_KEY, useClientEntitlement } from "@/components/client/use-client-entitlement";
import { safeVideoUrl } from "@/components/client/video";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

const FORM_REVIEWS_KEY = ["me", "form-reviews"] as const;

/** `/coaching`: form reviews and the nutrition plan, each shown when included. */
export function CoachingConsole() {
  const i18n = useUiTranslations();
  return (
    <ClientPage title={i18n("clCoachingTitle")} intro={i18n("clCoachingIntro")}>
      <FeatureGate feature="coaching">
        <CoachingContent />
      </FeatureGate>
    </ClientPage>
  );
}

function CoachingContent() {
  const i18n = useUiTranslations();
  const { entitlement, isError } = useClientEntitlement();
  // When the entitlement cannot be read, show both and let the API decide.
  const showReviews = isError || hasCapability(entitlement, "request_form_reviews");
  const showNutrition = isError || hasCapability(entitlement, "receive_nutrition_plan");
  const slaHours = responseSlaHours(entitlement);

  return (
    <div className="flex flex-col gap-4">
      {slaHours ? (
        <p
          className="rounded-xl px-4 py-3 text-sm"
          style={{
            background: "color-mix(in srgb, var(--info) 12%, transparent)",
            border: "1px solid color-mix(in srgb, var(--info) 30%, transparent)",
            color: "var(--text-soft)",
          }}
        >
          {i18n("clCoachResponseTime", { hours: slaHours })}
        </p>
      ) : null}
      {showReviews ? <FormReviews /> : null}
      {showNutrition ? <NutritionPlanCard /> : null}
    </div>
  );
}

function FormReviews() {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const { entitlement } = useClientEntitlement();
  const allowance = allowanceRemaining(entitlement, "form_reviews");
  const query = useQuery({
    queryKey: FORM_REVIEWS_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchMyFormReviews(tokens!.access_token),
  });
  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: FORM_REVIEWS_KEY });
    void queryClient.invalidateQueries({ queryKey: CLIENT_ENTITLEMENT_QUERY_KEY });
  };
  const withdraw = useMutation({
    mutationFn: (id: string) => withdrawFormReview(tokens!.access_token, id),
    onSuccess: refresh,
  });
  const usedUp = allowance != null && allowance.remaining !== "unlimited" && allowance.remaining <= 0;

  return (
    <ClientCard
      title={i18n("clFormReviewsTitle")}
      aside={
        allowance ? (
          <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>
            {allowance.remaining === "unlimited"
              ? i18n("clFormReviewsUnlimited")
              : allowance.limit === "unlimited"
                ? i18n("clFormReviewsLeft", { remaining: allowance.remaining })
                : i18n("clFormReviewsRemaining", { remaining: allowance.remaining, limit: allowance.limit })}
          </span>
        ) : null
      }
    >
      <p className="mb-3 text-sm" style={{ color: "var(--muted)" }}>{i18n("clFormReviewsIntro")}</p>
      {usedUp ? (
        <p className="mb-3 text-sm" style={{ color: "var(--warning)" }}>{i18n("clFormReviewUsedUp")}</p>
      ) : (
        <FormReviewForm onSubmitted={refresh} />
      )}

      <h3 className="mb-2 mt-5 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {i18n("clFormReviewHistory")}
      </h3>
      {withdraw.isError ? (
        <p role="alert" className="mb-2 text-sm" style={{ color: "var(--danger)" }}>
          {clientErrorMessage(withdraw.error, i18n)}
        </p>
      ) : null}
      {query.isPending ? (
        <LoadingLine />
      ) : query.isError ? (
        <QueryProblem error={query.error} onRetry={() => void query.refetch()} />
      ) : query.data.length === 0 ? (
        <EmptyLine>{i18n("clFormReviewEmpty")}</EmptyLine>
      ) : (
        <ul className="flex flex-col gap-2">
          {query.data.map((review) => (
            <FormReviewItem
              key={review.id}
              review={review}
              withdrawing={withdraw.isPending && withdraw.variables === review.id}
              onWithdraw={() => {
                if (window.confirm(i18n("clFormReviewWithdrawConfirm"))) withdraw.mutate(review.id);
              }}
            />
          ))}
        </ul>
      )}
    </ClientCard>
  );
}

function FormReviewForm({ onSubmitted }: { onSubmitted: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const id = useId();
  const [videoUrl, setVideoUrl] = useState("");
  const [exercise, setExercise] = useState("");
  const [note, setNote] = useState("");
  const [invalidUrl, setInvalidUrl] = useState(false);
  const [sent, setSent] = useState(false);
  const submit = useMutation({
    mutationFn: () =>
      submitFormReview(tokens!.access_token, {
        video_url: videoUrl.trim(),
        exercise_name: exercise.trim() || null,
        note: note.trim() || null,
      }),
    onSuccess: () => {
      setVideoUrl("");
      setExercise("");
      setNote("");
      setSent(true);
      onSubmitted();
    },
  });
  const inputClass = "w-full rounded-xl px-3 py-2 text-sm outline-none";
  const inputStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(event) => {
        event.preventDefault();
        setSent(false);
        if (!safeVideoUrl(videoUrl)) {
          setInvalidUrl(true);
          return;
        }
        setInvalidUrl(false);
        submit.mutate();
      }}
    >
      <div>
        <label htmlFor={`${id}-url`} className="mb-1 block text-xs font-semibold" style={{ color: "var(--muted)" }}>
          {i18n("clFormReviewVideoUrl")}
        </label>
        <input
          id={`${id}-url`}
          type="url"
          inputMode="url"
          required
          value={videoUrl}
          onChange={(event) => setVideoUrl(event.target.value)}
          aria-invalid={invalidUrl}
          aria-describedby={`${id}-url-help`}
          placeholder="https://"
          className={inputClass}
          style={inputStyle}
        />
        <p id={`${id}-url-help`} className="mt-1 text-xs" style={{ color: invalidUrl ? "var(--danger)" : "var(--dim)" }}>
          {invalidUrl ? i18n("clFormReviewInvalidUrl") : i18n("clFormReviewVideoHelp")}
        </p>
      </div>
      <div>
        <label htmlFor={`${id}-exercise`} className="mb-1 block text-xs font-semibold" style={{ color: "var(--muted)" }}>
          {i18n("clFormReviewExercise")}
        </label>
        <input
          id={`${id}-exercise`}
          value={exercise}
          maxLength={200}
          onChange={(event) => setExercise(event.target.value)}
          className={inputClass}
          style={inputStyle}
        />
      </div>
      <div>
        <label htmlFor={`${id}-note`} className="mb-1 block text-xs font-semibold" style={{ color: "var(--muted)" }}>
          {i18n("clFormReviewNote")}
        </label>
        <textarea
          id={`${id}-note`}
          value={note}
          rows={3}
          maxLength={2000}
          onChange={(event) => setNote(event.target.value)}
          className={inputClass}
          style={inputStyle}
        />
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <button
          type="submit"
          disabled={submit.isPending}
          className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {submit.isPending ? i18n("clSending") : i18n("clFormReviewSubmit")}
        </button>
        <span role="status" className="text-sm" style={{ color: submit.isError ? "var(--danger)" : "var(--success)" }}>
          {submit.isError ? clientErrorMessage(submit.error, i18n) : sent ? i18n("clFormReviewSubmitted") : ""}
        </span>
      </div>
    </form>
  );
}

function FormReviewItem({
  review,
  withdrawing,
  onWithdraw,
}: {
  review: FormReview;
  withdrawing: boolean;
  onWithdraw: () => void;
}) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const url = safeVideoUrl(review.video_url);
  const status =
    review.status === "reviewed"
      ? { label: i18n("clFormReviewStatusReviewed"), color: "var(--success)" }
      : review.status === "withdrawn"
        ? { label: i18n("clFormReviewStatusWithdrawn"), color: "var(--dim)" }
        : { label: i18n("clFormReviewStatusSubmitted"), color: "var(--warning)" };

  return (
    <li className="rounded-xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="break-words text-sm font-semibold" style={{ color: "var(--text)" }}>
            {review.exercise_name || i18n("clFormReviewsTitle")}
          </p>
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            {i18n("clFormReviewSentOn", { date: formatDateTime(review.inserted_at, locale) })}
          </p>
        </div>
        <span className="rounded-full px-2 py-0.5 text-[11px] font-semibold" style={{ background: `color-mix(in srgb, ${status.color} 14%, transparent)`, color: status.color }}>
          {status.label}
        </span>
      </div>
      {review.note ? (
        <p className="mt-2 whitespace-pre-line break-words text-sm" style={{ color: "var(--muted)" }}>{review.note}</p>
      ) : null}
      {review.feedback ? (
        <div className="mt-2 rounded-lg px-3 py-2" style={{ background: "color-mix(in srgb, var(--success) 10%, transparent)" }}>
          <p className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--success)" }}>
            {i18n("clFormReviewFeedback")}
          </p>
          <p className="mt-1 whitespace-pre-line break-words text-sm" style={{ color: "var(--text)" }}>{review.feedback}</p>
        </div>
      ) : null}
      <div className="mt-2 flex flex-wrap gap-2">
        {url ? (
          <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-full px-3 py-1 text-xs font-semibold"
            style={{ background: "var(--border)", color: "var(--text)" }}
          >
            {i18n("clFormReviewOpenVideo")}
          </a>
        ) : null}
        {review.status === "submitted" ? (
          <button
            type="button"
            onClick={onWithdraw}
            disabled={withdrawing}
            className="rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50"
            style={{ border: "1px solid var(--border)", color: "var(--danger)" }}
          >
            {i18n("clFormReviewWithdraw")}
          </button>
        ) : null}
      </div>
    </li>
  );
}

function NutritionPlanCard() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const query = useQuery({
    queryKey: ["me", "nutrition-plan"],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchMyNutritionPlan(tokens!.access_token),
  });
  const number = new Intl.NumberFormat(locale);
  const plan = query.data;
  const macros = plan
    ? [
        { key: "calories", label: i18n("clNutritionCalories"), value: plan.daily_calories, text: (v: number) => i18n("clNutritionKcal", { count: number.format(v) }) },
        { key: "protein", label: i18n("clNutritionProtein"), value: plan.protein_grams, text: (v: number) => i18n("clNutritionGrams", { count: number.format(v) }) },
        { key: "carbs", label: i18n("clNutritionCarbs"), value: plan.carbs_grams, text: (v: number) => i18n("clNutritionGrams", { count: number.format(v) }) },
        { key: "fat", label: i18n("clNutritionFat"), value: plan.fat_grams, text: (v: number) => i18n("clNutritionGrams", { count: number.format(v) }) },
      ].filter((macro): macro is typeof macro & { value: number } => typeof macro.value === "number")
    : [];

  return (
    <ClientCard title={i18n("clNutritionTitle")}>
      {query.isPending ? (
        <LoadingLine />
      ) : query.isError ? (
        <QueryProblem error={query.error} onRetry={() => void query.refetch()} />
      ) : !plan ? (
        <EmptyLine>{i18n("clNutritionEmpty")}</EmptyLine>
      ) : (
        <div className="flex flex-col gap-3">
          <div>
            <h3 className="break-words text-lg font-semibold" style={{ color: "var(--text)" }}>{plan.title}</h3>
            {plan.updated_at ? (
              <p className="text-xs" style={{ color: "var(--dim)" }}>
                {i18n("clNutritionUpdated", { date: formatDateTime(plan.updated_at, locale) })}
              </p>
            ) : null}
          </div>
          {macros.length > 0 ? (
            <dl className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {macros.map((macro) => (
                <div key={macro.key} className="rounded-xl px-3 py-2" style={{ background: "var(--panel-muted)" }}>
                  <dt className="text-xs uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{macro.label}</dt>
                  <dd className="mt-0.5 text-base font-semibold tabular-nums" style={{ color: "var(--text)" }}>{macro.text(macro.value)}</dd>
                </div>
              ))}
            </dl>
          ) : null}
          <p className="whitespace-pre-line break-words text-sm leading-6" style={{ color: "var(--text-soft)" }}>{plan.body}</p>
        </div>
      )}
    </ClientCard>
  );
}

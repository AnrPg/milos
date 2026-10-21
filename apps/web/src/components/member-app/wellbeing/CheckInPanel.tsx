"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";
import { useMemo, useState } from "react";

import { deleteMyCheckIn, fetchMyCheckIns, submitCheckIn, type CheckInRecord } from "@/api/wellbeing";
import { HubCard } from "@/components/member-app/HubParts";
import { prGymSlugForSubmit, usePRGymOptions } from "@/components/pantheon/PRGymField";
import { useSession } from "@/components/session-provider";

import {
  CHECK_IN_FACES,
  CHECK_IN_VALUES,
  draftAnswers,
  latestAnswers,
  questionTimeline,
  timelineWindow,
  toggleAnswer,
  type CheckInDraft,
  type CheckInValue,
} from "./check-in";

const TIMELINE_DAYS = 14;
const QUESTION_KEYS = ["sleep", "energy", "mood", "stress", "body"] as const;

/**
 * Πώς νιώθω (ADR-140 §2): a few questions answered with one of four faces;
 * an answer opens an optional text field under its question. Every
 * submission is a new timestamped entry; below, each question draws a
 * timeline with a point per submission. Questions Ευεξία already answered
 * that day (sleep) are skipped.
 */
export function CheckInPanel({ skipQuestions = [] }: { skipQuestions?: string[] } = {}) {
  const t = useTranslations("MemberApp.checkIn");
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const { defaultGymSlug } = usePRGymOptions();
  const [draft, setDraft] = useState<CheckInDraft>({});
  const [savedAt, setSavedAt] = useState<string | null>(null);
  const range = useMemo(() => timelineWindow(new Date(), TIMELINE_DAYS), []);

  const timelineQuery = useQuery({
    queryKey: ["my", "wellbeing", "check-ins", range.from.toISOString()],
    enabled: Boolean(tokens?.access_token),
    queryFn: () =>
      fetchMyCheckIns(tokens!.access_token, { from: range.from.toISOString(), to: range.to.toISOString() }),
  });

  // ADR-159 (board 14, Q3): no sleep question on a day the night is already logged.
  const questionKeys = (timelineQuery.data?.questions.map((question) => question.key) ?? [...QUESTION_KEYS]).filter(
    (key) => !skipQuestions.includes(key),
  );
  const answers = draftAnswers(draft, questionKeys);

  const submitMutation = useMutation({
    mutationFn: () =>
      submitCheckIn(tokens!.access_token, {
        answers,
        organization_slug: prGymSlugForSubmit(defaultGymSlug),
        recorded_tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      }),
    onSuccess: ({ check_in }) => {
      setDraft({});
      setSavedAt(check_in.recorded_at);
      void queryClient.invalidateQueries({ queryKey: ["my", "wellbeing", "check-ins"] });
    },
  });

  return (
    <div className="space-y-4">
      <HubCard eyebrow={t("eyebrow")}>
        <form
          className="space-y-4"
          onSubmit={(event) => {
            event.preventDefault();
            if (answers.length > 0) submitMutation.mutate();
          }}
        >
          <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t("title")}</h2>
          {questionKeys.map((key) => (
            <fieldset key={key} className="space-y-2">
              <legend className="text-sm font-bold" style={{ color: "var(--text)" }}>{t(`question.${key}`)}</legend>
              <div className="grid grid-cols-4 gap-2">
                {CHECK_IN_VALUES.map((value) => (
                  <AnswerButton
                    key={value}
                    value={value}
                    label={t(`answer.${key}.${value}`)}
                    selected={draft[key]?.value === value}
                    onClick={() => setDraft((current) => toggleAnswer(current, key, value))}
                  />
                ))}
              </div>
              {draft[key] ? (
                <textarea
                  aria-label={t("notePlaceholder")}
                  className="min-h-16 w-full rounded-2xl px-4 py-3 text-sm outline-none"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                  maxLength={1000}
                  placeholder={t("notePlaceholder")}
                  value={draft[key].note}
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, [key]: { ...current[key], note: event.target.value } }))
                  }
                />
              ) : null}
            </fieldset>
          ))}
          <button
            type="submit"
            disabled={answers.length === 0 || submitMutation.isPending}
            className="min-h-11 w-full rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--bg)" }}
          >
            {submitMutation.isPending ? t("saving") : t("save")}
          </button>
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            {answers.length === 0 ? t("answerOne") : t("savesAsNew")}
          </p>
          {savedAt ? <SavedLine at={savedAt} /> : null}
          {submitMutation.isError ? (
            <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("saveFailed")}</p>
          ) : null}
        </form>
      </HubCard>

      <CheckInTimeline
        checkIns={timelineQuery.data?.check_ins ?? []}
        questionKeys={questionKeys}
        from={range.from}
        to={range.to}
        loading={timelineQuery.isLoading}
      />
    </div>
  );
}

function AnswerButton({
  value,
  label,
  selected,
  onClick,
}: {
  value: CheckInValue;
  label: string;
  selected: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className="flex min-h-16 flex-col items-center justify-center gap-1 rounded-2xl px-1 text-[11px] font-semibold leading-tight"
      style={{
        background: selected ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel-raised)",
        border: `1px solid ${selected ? "var(--primary)" : "var(--border)"}`,
        color: "var(--text)",
      }}
    >
      <span aria-hidden className="text-2xl">{CHECK_IN_FACES[value]}</span>
      {label}
    </button>
  );
}

function SavedLine({ at }: { at: string }) {
  const t = useTranslations("MemberApp.checkIn");
  const format = useFormatter();
  return (
    <p className="text-sm font-semibold" style={{ color: "var(--success, var(--primary-strong))" }}>
      {t("saved", { time: format.dateTime(new Date(at), { hour: "2-digit", minute: "2-digit" }) })}
    </p>
  );
}

function CheckInTimeline({
  checkIns,
  questionKeys,
  from,
  to,
  loading,
}: {
  checkIns: CheckInRecord[];
  questionKeys: string[];
  from: Date;
  to: Date;
  loading: boolean;
}) {
  const t = useTranslations("MemberApp.checkIn");
  const format = useFormatter();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const latest = latestAnswers(checkIns);

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteMyCheckIn(tokens!.access_token, id),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["my", "wellbeing", "check-ins"] }),
  });

  return (
    <HubCard eyebrow={t("timelineTitle", { days: TIMELINE_DAYS })}>
      {loading ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("loading")}</p>
      ) : checkIns.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("timelineEmpty")}</p>
      ) : (
        <div className="space-y-4">
          {questionKeys.map((key) => {
            const points = questionTimeline(checkIns, key, from, to);
            const current = latest[key];
            return (
              <div key={key} className="space-y-1">
                <div className="flex items-baseline justify-between gap-2 text-sm">
                  <span className="font-bold" style={{ color: "var(--text)" }}>{t(`short.${key}`)}</span>
                  <span style={{ color: "var(--muted)" }}>
                    {current ? `${CHECK_IN_FACES[current.value as CheckInValue]} ${t(`answer.${key}.${current.value}`)}` : "—"}
                  </span>
                </div>
                <svg
                  role="img"
                  aria-label={t("timelineAria", { question: t(`short.${key}`), count: points.length })}
                  viewBox="0 0 300 48"
                  className="h-12 w-full"
                  preserveAspectRatio="none"
                >
                  <line x1="0" x2="300" y1="44" y2="44" stroke="var(--border)" strokeWidth="1" />
                  {points.length > 1 ? (
                    <polyline
                      fill="none"
                      stroke="var(--primary)"
                      strokeWidth="1.5"
                      vectorEffect="non-scaling-stroke"
                      points={points.map((point) => `${point.x * 300},${40 - point.y * 34}`).join(" ")}
                    />
                  ) : null}
                  {points.map((point) => (
                    <circle
                      key={point.id}
                      cx={point.x * 300}
                      cy={40 - point.y * 34}
                      r="3.5"
                      fill={point.note ? "var(--primary-strong)" : "var(--primary)"}
                    >
                      <title>
                        {`${format.dateTime(new Date(point.at), { dateStyle: "short", timeStyle: "short" })} · ${t(`answer.${key}.${point.value}`)}${point.note ? ` · ${point.note}` : ""}`}
                      </title>
                    </circle>
                  ))}
                </svg>
              </div>
            );
          })}

          <details>
            <summary className="cursor-pointer text-sm font-bold" style={{ color: "var(--text)" }}>
              {t("history", { count: checkIns.length })}
            </summary>
            <ol className="mt-2 space-y-2">
              {[...checkIns].reverse().map((checkIn) => (
                <li
                  key={checkIn.id}
                  className="rounded-2xl p-3 text-sm"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-semibold" style={{ color: "var(--text)" }}>
                      {format.dateTime(new Date(checkIn.recorded_at), { dateStyle: "medium", timeStyle: "short" })}
                    </span>
                    <button
                      type="button"
                      className="text-xs font-semibold"
                      style={{ color: "var(--danger)" }}
                      onClick={() => deleteMutation.mutate(checkIn.id)}
                    >
                      {t("delete")}
                    </button>
                  </div>
                  <ul className="mt-1 space-y-0.5">
                    {checkIn.answers.map((answer) => (
                      <li key={answer.question_key} style={{ color: "var(--muted)" }}>
                        {CHECK_IN_FACES[answer.value as CheckInValue]} {t(`short.${answer.question_key}`)}:{" "}
                        {t(`answer.${answer.question_key}.${answer.value}`)}
                        {answer.note ? <span style={{ color: "var(--text)" }}> · {answer.note}</span> : null}
                      </li>
                    ))}
                  </ul>
                </li>
              ))}
            </ol>
          </details>
        </div>
      )}
    </HubCard>
  );
}

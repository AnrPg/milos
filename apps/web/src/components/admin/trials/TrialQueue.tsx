"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { getOrCreateContextThread } from "@/api/messaging";
import {
  acceptTrial,
  declineTrial,
  fetchTrialQueue,
  recordTrialAttendance,
  TRIAL_STAGES,
  trialQueueKey,
  type StaffTrial,
  type TrialStage,
} from "@/api/trials";
import { useSession } from "@/components/session-provider";
import { StatusPill } from "@/components/trials/TrialPage";
import { trialErrorKey } from "@/components/trials/trial-ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { can } from "@/lib/role-navigation";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * Staff's trial queue (board 6 Q4): Αιτήματα · Επερχόμενα · Ήρθαν · Έγιναν
 * μέλη, with accept or decline, attended or not, and a message to the
 * person; the last 30 days in numbers on top.
 */
export function TrialQueue() {
  const t = useTranslations("Trials");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const { membership } = useSelectedMembershipRole();
  const [stage, setStage] = useState<TrialStage>("requests");
  const queue = useQuery({ queryKey: trialQueueKey(stage), enabled: Boolean(token), queryFn: () => fetchTrialQueue(token, stage) });
  const stats = queue.data?.stats;

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-3xl flex-col gap-5 pb-28">
        <header className="flex flex-wrap items-center justify-between gap-3">
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("queueTitle")}</h1>
          {can(membership, "manage_settings") ? (
            <Link
              href={adminHref("/admin/trials/settings", slug)}
              className="rounded-2xl px-4 py-2 text-sm font-bold"
              style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("settingsLink")}
            </Link>
          ) : null}
        </header>

        {stats ? (
          <section aria-label={t("statsTitle", { days: stats.days })} className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {(
              [
                ["statRequested", stats.requested + stats.booked + stats.attended + stats.no_show + stats.converted],
                ["statAttended", stats.attended + stats.converted],
                ["statNoShow", stats.no_show],
                ["statConverted", stats.converted],
              ] as const
            ).map(([key, value]) => (
              <div key={key} className="rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <p className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{value}</p>
                <p className="text-xs" style={{ color: "var(--dim)" }}>{t(key, { days: stats.days })}</p>
              </div>
            ))}
          </section>
        ) : null}

        <SegmentPicker
          ariaLabel={t("queueTitle")}
          value={stage}
          onChange={setStage}
          options={TRIAL_STAGES.map((value) => ({ value, label: t(`stage_${value}`), count: queue.data?.counts[value] || null }))}
        />

        {queue.isPending ? <p className="py-8 text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
        {queue.isError ? <ErrorNotice className="my-8">{t(trialErrorKey(queue.error))}</ErrorNotice> : null}
        {queue.isSuccess && queue.data.trials.length === 0 ? (
          <p className="rounded-2xl p-6 text-center text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
            {t(`stageEmpty_${stage}`)}
          </p>
        ) : null}
        <ul className="flex flex-col gap-3">
          {queue.data?.trials.map((trial) => (
            <li key={trial.id}>
              <TrialRow trial={trial} token={token} stage={stage} />
            </li>
          ))}
        </ul>
      </div>
    </main>
  );
}

function TrialRow({ trial, token, stage }: { trial: StaffTrial; token: string; stage: TrialStage }) {
  const t = useTranslations("Trials");
  const locale = useLocale();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [declining, setDeclining] = useState(false);
  const [reason, setReason] = useState("");
  const refresh = () => TRIAL_STAGES.forEach((value) => void queryClient.invalidateQueries({ queryKey: trialQueueKey(value) }));
  const action = useMutation({
    mutationFn: async (kind: "accept" | "decline" | "attended" | "no_show") => {
      if (kind === "accept") return acceptTrial(token, trial.id);
      if (kind === "decline") return declineTrial(token, trial.id, reason.trim() || null);
      return recordTrialAttendance(token, trial.id, kind);
    },
    onSuccess: () => {
      setDeclining(false);
      refresh();
    },
  });
  const message = useMutation({
    mutationFn: () => getOrCreateContextThread(token, "box", (trial.user_id ?? trial.person?.id)!),
    onSuccess: ({ thread }) => router.push(`/messages?thread=${encodeURIComponent(thread.id)}`),
  });

  const start = new Date(trial.class.scheduled_at);
  const when = new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(start);
  const name = trial.person?.nickname ?? t("someone");
  const started = start <= new Date();
  const button = "min-h-10 flex-1 rounded-2xl px-3 text-sm font-bold disabled:opacity-60";

  return (
    <article className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 flex-col">
          <span className="truncate text-base font-bold" style={{ color: "var(--text)" }}>{name}</span>
          <span className="text-sm first-letter:uppercase" style={{ color: "var(--text-soft)" }}>
            {trial.class.name} · {when}
          </span>
          {trial.phone ? (
            <span className="select-all text-sm" style={{ color: "var(--text-soft)" }}>{trial.phone}</span>
          ) : null}
        </div>
        <StatusPill status={trial.status} />
      </div>
      {trial.note ? (
        <p className="whitespace-pre-line rounded-xl px-3 py-2 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>{trial.note}</p>
      ) : null}
      {trial.join_interest_at && trial.status !== "converted" ? (
        <p className="text-sm font-semibold" style={{ color: "var(--success)" }}>{t("wantsToJoin")}</p>
      ) : null}
      {action.isError ? <ErrorNotice>{t(trialErrorKey(action.error))}</ErrorNotice> : null}

      {declining ? (
        <div className="flex flex-col gap-2">
          <label className="flex flex-col gap-1">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("declineReason")}</span>
            <input
              value={reason}
              maxLength={300}
              onChange={(event) => setReason(event.target.value)}
              className="min-h-11 rounded-2xl px-3 text-sm"
              style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </label>
          <div className="flex gap-2">
            <button type="button" disabled={action.isPending} onClick={() => action.mutate("decline")} className={button} style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}>
              {t("decline")}
            </button>
            <button type="button" onClick={() => setDeclining(false)} className={button} style={{ color: "var(--text-soft)" }}>
              {t("cancel")}
            </button>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          {stage === "requests" && trial.status === "requested" ? (
            <>
              <button type="button" disabled={action.isPending} onClick={() => action.mutate("accept")} className={button} style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                {t("accept")}
              </button>
              <button type="button" onClick={() => setDeclining(true)} className={button} style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
                {t("decline")}
              </button>
            </>
          ) : null}
          {stage === "upcoming" && trial.status === "booked" && started ? (
            <>
              <button type="button" disabled={action.isPending} onClick={() => action.mutate("attended")} className={button} style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                {t("markAttended")}
              </button>
              <button type="button" disabled={action.isPending} onClick={() => action.mutate("no_show")} className={button} style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
                {t("markNoShow")}
              </button>
            </>
          ) : null}
          <button
            type="button"
            disabled={message.isPending || !(trial.user_id ?? trial.person?.id)}
            onClick={() => message.mutate()}
            className={button}
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("sendMessage")}
          </button>
        </div>
      )}
    </article>
  );
}

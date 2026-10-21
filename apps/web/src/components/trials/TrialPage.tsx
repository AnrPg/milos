"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, useSyncExternalStore } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import {
  boxConversationKey,
  cancelTrial,
  fetchMyTrial,
  followUpTrial,
  MY_TRIALS_KEY,
  myTrialKey,
  trialCalendarFile,
  type MyTrial,
} from "@/api/trials";
import { useSession } from "@/components/session-provider";
import { mapsSearchUrl, mapsUrl, readApple, serverApple, subscribeNever } from "@/lib/maps";

import { downloadFile, trialErrorKey } from "./trial-ui";

const OPEN = new Set(["requested", "booked"]);

/**
 * One trial (board 6 Q5): where it stands, the class, the box and how to get
 * there, «Τι να φέρεις», add to calendar, cancel while it's open, and after
 * the visit «Πώς σου φάνηκε;» with «Θέλω να γραφτώ».
 */
export function TrialPage({ trialId }: { trialId: string }) {
  const t = useTranslations("Trials");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const trial = useQuery({ queryKey: myTrialKey(trialId), enabled: Boolean(token), queryFn: () => fetchMyTrial(token, trialId) });
  const apple = useSyncExternalStore(subscribeNever, readApple, serverApple);

  if (trial.isPending) return <Shell><p className="py-10 text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p></Shell>;
  if (trial.isError || !trial.data)
    return (
      <Shell>
        <p className="py-10 text-center text-sm" style={{ color: "var(--text-soft)" }}>{t("notFound")}</p>
      </Shell>
    );

  const data = trial.data;
  const start = new Date(data.class.scheduled_at);
  const when = new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long" }).format(start);
  const clock = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(start);
  const place = data.location;
  const address = [place?.address, place?.neighbourhood, place?.city].filter(Boolean).join(", ");
  const directions = place
    ? place.latitude != null && place.longitude != null
      ? mapsUrl({ latitude: place.latitude, longitude: place.longitude }, data.box?.name ?? place.name, apple)
      : address
        ? mapsSearchUrl(address, apple)
        : null
    : null;
  const open = OPEN.has(data.status);
  const upcoming = open && start > new Date();

  return (
    <Shell>
      <header className="flex flex-col gap-2">
        {data.box ? (
          <Link href={`/b/${data.box.slug}`} className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {data.box.name}
          </Link>
        ) : null}
        <h1 className="text-3xl font-extrabold" style={{ color: "var(--text)" }}>{data.class.name ?? t("trialTitle")}</h1>
        <p className="text-sm font-semibold first-letter:uppercase" style={{ color: "var(--text-soft)" }}>
          {when} · {clock}
          {data.class.duration_minutes ? ` · ${t("minutes", { count: data.class.duration_minutes })}` : ""}
        </p>
        <StatusPill status={data.status} />
      </header>

      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`statusLine_${data.status}`)}</p>
      {data.status === "declined" && data.decline_reason ? (
        <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
          {data.decline_reason}
        </p>
      ) : null}

      {data.follow_up && data.box ? <FollowUp trial={data} token={token} /> : null}

      {place ? (
        <section className="flex flex-col gap-1 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("where")}</p>
          <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{place.name}</p>
          {address ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{address}</p> : null}
          {directions ? (
            <a href={directions} target="_blank" rel="noreferrer" className="mt-1 text-sm font-bold" style={{ color: "var(--primary-strong)" }}>
              {t("directions")} ↗
            </a>
          ) : null}
        </section>
      ) : null}

      {data.bring_note && open ? (
        <section className="flex flex-col gap-1 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("bringTitle")}</p>
          <p className="whitespace-pre-line text-sm" style={{ color: "var(--text)" }}>{data.bring_note}</p>
        </section>
      ) : null}

      {data.note ? (
        <section className="flex flex-col gap-1 px-1">
          <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("yourNote")}</p>
          <p className="whitespace-pre-line text-sm" style={{ color: "var(--text-soft)" }}>{data.note}</p>
        </section>
      ) : null}

      <div className="flex flex-col gap-2">
        {upcoming ? (
          <button
            type="button"
            onClick={() => downloadFile(`trial-${data.id}.ics`, "text/calendar", trialCalendarFile(data, t("calendarTitle", { box: data.box?.name ?? "", name: data.class.name ?? "" })))}
            className="flex min-h-12 items-center justify-center rounded-2xl text-sm font-bold"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("addToCalendar")}
          </button>
        ) : null}
        {data.box ? (
          <Link
            href={`/b/${data.box.slug}/chat`}
            className="flex min-h-12 items-center justify-center rounded-2xl text-sm font-bold"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("messageBox")}
          </Link>
        ) : null}
        {upcoming ? <CancelTrial trial={data} token={token} /> : null}
      </div>
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return <main className="mx-auto flex w-full max-w-xl flex-col gap-5 px-4 pb-28 pt-6">{children}</main>;
}

export function StatusPill({ status }: { status: MyTrial["status"] }) {
  const t = useTranslations("Trials");
  const tone =
    status === "booked" || status === "attended" || status === "converted"
      ? "var(--success)"
      : status === "requested"
        ? "var(--warning)"
        : "var(--dim)";
  return (
    <span
      className="w-fit rounded-full px-2.5 py-1 text-xs font-bold"
      style={{ background: `color-mix(in srgb, ${tone} 15%, transparent)`, color: tone }}
    >
      {t(`status_${status}`)}
    </span>
  );
}

function CancelTrial({ trial, token }: { trial: MyTrial; token: string }) {
  const t = useTranslations("Trials");
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const cancel = useMutation({
    mutationFn: () => cancelTrial(token, trial.id),
    onSuccess: (next) => {
      queryClient.setQueryData(myTrialKey(trial.id), next);
      void queryClient.invalidateQueries({ queryKey: MY_TRIALS_KEY });
      void queryClient.invalidateQueries({ queryKey: ["social", "box-schedule"] });
      setConfirming(false);
    },
  });
  if (!confirming)
    return (
      <button type="button" onClick={() => setConfirming(true)} className="min-h-11 rounded-2xl text-sm font-bold" style={{ color: "var(--danger)" }}>
        {t("cancelTrial")}
      </button>
    );
  return (
    <div className="flex flex-col gap-2 rounded-2xl p-4" style={{ border: "1px solid var(--danger)" }}>
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("cancelConfirm")}</p>
      {cancel.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t(trialErrorKey(cancel.error))}</p> : null}
      <div className="flex gap-2">
        <button
          type="button"
          disabled={cancel.isPending}
          onClick={() => cancel.mutate()}
          className="min-h-11 flex-1 rounded-2xl text-sm font-bold disabled:opacity-60"
          style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
        >
          {t("cancelYes")}
        </button>
        <button type="button" onClick={() => setConfirming(false)} className="min-h-11 flex-1 rounded-2xl text-sm font-bold" style={{ color: "var(--text-soft)" }}>
          {t("cancelNo")}
        </button>
      </div>
    </div>
  );
}

/** «Πώς σου φάνηκε;» (board 6 Q6): join opens the chat with the box, prefilled. */
export function FollowUp({ trial, token, compact }: { trial: MyTrial; token: string; compact?: boolean }) {
  const t = useTranslations("Trials");
  const router = useRouter();
  const queryClient = useQueryClient();
  const answer = useMutation({
    mutationFn: (action: "join" | "dismiss") => followUpTrial(token, trial.id, action),
    onSuccess: ({ trial: next, conversation }, action) => {
      queryClient.setQueryData(myTrialKey(trial.id), next);
      void queryClient.invalidateQueries({ queryKey: MY_TRIALS_KEY });
      if (action === "join" && trial.box) {
        if (conversation) queryClient.setQueryData(boxConversationKey(trial.box.slug), conversation);
        router.push(`/b/${trial.box.slug}/chat?draft=join`);
      }
    },
  });
  return (
    <section
      className={`flex flex-col gap-3 rounded-3xl ${compact ? "" : "p-5"}`}
      style={compact ? undefined : { background: "color-mix(in srgb, var(--primary) 8%, var(--panel))", border: "1px solid color-mix(in srgb, var(--primary) 45%, transparent)" }}
    >
      <div className="flex flex-col gap-1">
        <p className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("followUpTitle")}</p>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("followUpBody", { box: trial.box?.name ?? "" })}</p>
      </div>
      {answer.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t(trialErrorKey(answer.error))}</p> : null}
      <div className="flex gap-2">
        <button
          type="button"
          disabled={answer.isPending}
          onClick={() => answer.mutate("join")}
          className="min-h-11 flex-1 rounded-2xl text-sm font-bold disabled:opacity-60"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("followUpJoin")}
        </button>
        <button
          type="button"
          disabled={answer.isPending}
          onClick={() => answer.mutate("dismiss")}
          className="min-h-11 flex-1 rounded-2xl text-sm font-bold disabled:opacity-60"
          style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}
        >
          {t("followUpDismiss")}
        </button>
      </div>
    </section>
  );
}

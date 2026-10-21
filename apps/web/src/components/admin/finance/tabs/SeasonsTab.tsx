"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useMemo, useState, type ReactNode } from "react";

import { fetchFinancePackages } from "@/api/finance";
import {
  STAFF_SEASONS_KEY,
  actOnSeasonEnrollment,
  cleanProgramme,
  createSeason,
  fetchStaffSeason,
  fetchStaffSeasons,
  programmeDate,
  staffSeasonKey,
  updateSeason,
  type EnrollmentAction,
  type SeasonCoachCandidate,
  type StaffSeason,
  type StaffSeasonDetail,
  type StaffSeasonEnrollment,
} from "@/api/seasons";
import { listAdminWorkouts } from "@/api/workouts";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { seasonDate, seasonErrorKey, seasonMoney, seasonRange, statusTone } from "@/components/seasons/season-ui";
import { useSession } from "@/components/session-provider";

/**
 * Seasons (ADR-167): the gym's fixed-length programmes, sold next to its
 * packages. One list and one sheet: the sheet builds the season (dates,
 * places, price, package, coaches, programme) and answers requests for
 * places. `?season=ID` opens a season, `?season=new` a blank one.
 */
export function SeasonsTab() {
  const t = useTranslations("Seasons");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const router = useRouter();
  const searchParams = useSearchParams();
  const openId = searchParams.get("season");

  const setSeason = useCallback(
    (value: string | null) => {
      const params = new URLSearchParams(searchParams.toString());
      if (value === null) params.delete("season");
      else params.set("season", value);
      router.replace(`?${params.toString()}`, { scroll: false });
    },
    [router, searchParams],
  );

  const seasons = useQuery({
    queryKey: STAFF_SEASONS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchStaffSeasons(token),
  });
  const list = (seasons.data?.seasons ?? []).filter((season) => season?.id);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("adminHint")}</p>
        <button
          className="shrink-0 rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
          onClick={() => setSeason("new")}
          type="button"
        >
          {t("newSeason")}
        </button>
      </div>

      <div className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {seasons.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : list.length === 0 ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{t("adminEmpty")}</p>
        ) : (
          <ul>
            {list.map((season, index) => (
              <li key={season.id} style={{ borderTop: index === 0 ? "none" : "1px solid var(--border)" }}>
                <SeasonRow season={season} locale={locale} onOpen={() => setSeason(season.id)} />
              </li>
            ))}
          </ul>
        )}
      </div>

      {openId ? (
        <SeasonPanel
          key={openId}
          id={openId === "new" ? null : openId}
          token={token}
          coachCandidates={seasons.data?.coachCandidates ?? []}
          onCreated={(id) => setSeason(id)}
          onClose={() => setSeason(null)}
        />
      ) : null}
    </div>
  );
}

function SeasonRow({ season, locale, onOpen }: { season: StaffSeason; locale: string; onOpen: () => void }) {
  const t = useTranslations("Seasons");
  const counts = season.counts ?? { active: 0, requested: 0, waitlisted: 0 };
  const waiting = (counts.requested ?? 0) + (counts.waitlisted ?? 0);
  return (
    <button type="button" onClick={onOpen} className="flex w-full flex-wrap items-center gap-x-4 gap-y-1 px-6 py-4 text-left">
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{season.title}</span>
        <span className="block text-xs" style={{ color: "var(--muted)" }}>
          {seasonRange(locale, season.starts_on, season.ends_on)} · {seasonMoney(locale, season.price_cents, season.currency)}
        </span>
      </span>
      <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
        {t("filled", { active: counts.active ?? 0, capacity: season.capacity ?? 0 })}
      </span>
      {waiting > 0 ? (
        <span className="rounded-full px-2.5 py-0.5 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--warning) 15%, transparent)", color: "var(--warning)" }}>
          {t("waiting", { count: waiting })}
        </span>
      ) : null}
      <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: statusTone(season.status) }}>
        {t(`status_${season.status ?? "draft"}`)}
      </span>
    </button>
  );
}

type Draft = {
  title: string;
  description: string;
  welcome_message: string;
  starts_on: string;
  weeks: string;
  capacity: string;
  price: string;
  membership_package_id: string;
  coach_ids: string[];
  programme: Array<{ day: number; workout_id: string }>;
};

function draftFrom(season: StaffSeasonDetail | null): Draft {
  return {
    title: season?.title ?? "",
    description: season?.description ?? "",
    welcome_message: season?.welcome_message ?? "",
    starts_on: season?.starts_on ?? "",
    weeks: String(season?.weeks ?? 6),
    capacity: String(season?.capacity ?? 12),
    price: season ? ((season.price_cents ?? 0) / 100).toFixed(2) : "",
    membership_package_id: season?.membership_package_id ?? "",
    coach_ids: season?.coach_ids ?? [],
    programme: (season?.programme ?? []).map((item) => ({ day: item.day, workout_id: item.workout_id })),
  };
}

function SeasonPanel({
  id,
  token,
  coachCandidates,
  onCreated,
  onClose,
}: {
  id: string | null;
  token: string;
  coachCandidates: SeasonCoachCandidate[];
  onCreated: (id: string) => void;
  onClose: () => void;
}) {
  const t = useTranslations("Seasons");
  const detail = useQuery({
    queryKey: staffSeasonKey(id ?? "new"),
    enabled: Boolean(token && id),
    queryFn: () => fetchStaffSeason(token, id!),
  });

  const title = id ? detail.data?.title || t("season") : t("newSeason");
  return (
    <SidePanel title={title} subtitle={t("eyebrow")} onClose={onClose} width="md:max-w-[640px]">
      {id && detail.isLoading ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : id && !detail.data ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("error_generic")}</p>
      ) : (
        <SeasonEditor
          key={detail.data?.id ?? "new"}
          season={detail.data ?? null}
          token={token}
          coachCandidates={coachCandidates}
          onCreated={onCreated}
        />
      )}
    </SidePanel>
  );
}

const inputClass = "w-full rounded-xl px-3 py-2 text-sm";
const inputStyle = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" } as const;

function SeasonEditor({
  season,
  token,
  coachCandidates,
  onCreated,
}: {
  season: StaffSeasonDetail | null;
  token: string;
  coachCandidates: SeasonCoachCandidate[];
  onCreated: (id: string) => void;
}) {
  const t = useTranslations("Seasons");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<Draft>(() => draftFrom(season));
  const status = season?.status ?? "draft";
  const closed = status === "completed" || status === "cancelled";
  const locked = (season?.counts?.active ?? 0) > 0;
  const weeks = Math.max(1, Math.min(52, Math.floor(Number(draft.weeks) || 1)));

  const packages = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackages(token),
  });
  const packageOptions = (packages.data?.packages ?? []).filter((pkg) => pkg?.id && pkg.active !== false);

  const workouts = useQuery({
    queryKey: ["admin", "workouts"],
    enabled: Boolean(token),
    queryFn: () => listAdminWorkouts(token),
  });
  const workoutOptions = useMemo(
    () => (Array.isArray(workouts.data) ? workouts.data : []).filter((workout) => workout?.id && workout.status === "published"),
    [workouts.data],
  );

  async function refresh(saved?: StaffSeasonDetail) {
    if (saved?.id) queryClient.setQueryData(staffSeasonKey(saved.id), saved);
    await queryClient.invalidateQueries({ queryKey: STAFF_SEASONS_KEY });
  }

  const save = useMutation({
    mutationFn: (publish: "published" | "cancelled" | null) => {
      const body = {
        title: draft.title.trim(),
        description: draft.description.trim() || null,
        welcome_message: draft.welcome_message.trim() || null,
        capacity: Math.max(1, Math.floor(Number(draft.capacity) || 1)),
        price_cents: Math.max(0, Math.round((Number(draft.price.replace(",", ".")) || 0) * 100)),
        membership_package_id: draft.membership_package_id || null,
        coach_ids: draft.coach_ids,
        ...(locked ? {} : { starts_on: draft.starts_on, weeks, programme: cleanProgramme(draft.programme, weeks) }),
        ...(publish ? { status: publish } : {}),
      };
      return season
        ? updateSeason(token, season.id, body)
        : createSeason(token, { ...body, starts_on: draft.starts_on, weeks, status: publish === "published" ? "published" : "draft" });
    },
    onSuccess: async (saved) => {
      await refresh(saved);
      if (!season && saved?.id) onCreated(saved.id);
    },
  });

  const [confirmingCancel, setConfirmingCancel] = useState(false);
  const canSave = draft.title.trim().length >= 2 && Boolean(draft.starts_on) && !closed && !save.isPending;

  function set<K extends keyof Draft>(key: K, value: Draft[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  return (
    <div className="space-y-6">
      {season ? (
        <p className="text-sm" style={{ color: statusTone(status) }}>
          <span className="font-semibold">{t(`status_${status}`)}</span>
          <span style={{ color: "var(--muted)" }}> · {seasonRange(locale, season.starts_on, season.ends_on)}</span>
        </p>
      ) : null}

      <fieldset disabled={closed} className="space-y-4">
        <Field label={t("fieldTitle")}>
          <input className={inputClass} style={inputStyle} maxLength={80} value={draft.title} onChange={(event) => set("title", event.target.value)} />
        </Field>
        <Field label={t("fieldDescription")}>
          <textarea className={inputClass} style={inputStyle} rows={3} maxLength={2000} value={draft.description} onChange={(event) => set("description", event.target.value)} />
        </Field>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Field label={t("fieldStartsOn")}>
            <input type="date" className={inputClass} style={inputStyle} disabled={locked} value={draft.starts_on} onChange={(event) => set("starts_on", event.target.value)} />
          </Field>
          <Field label={t("weeksLabel")}>
            <input type="number" min={1} max={52} className={inputClass} style={inputStyle} disabled={locked} value={draft.weeks} onChange={(event) => set("weeks", event.target.value)} />
          </Field>
          <Field label={t("fieldCapacity")}>
            <input type="number" min={1} max={500} className={inputClass} style={inputStyle} value={draft.capacity} onChange={(event) => set("capacity", event.target.value)} />
          </Field>
          <Field label={t("price")}>
            <input inputMode="decimal" className={inputClass} style={inputStyle} value={draft.price} placeholder="0.00" onChange={(event) => set("price", event.target.value)} />
          </Field>
        </div>
        {locked ? <p className="text-xs" style={{ color: "var(--warning)" }}>{t("scheduleLocked")}</p> : null}

        <Field label={t("fieldPackage")} hint={t("fieldPackageHint")}>
          <select className={inputClass} style={inputStyle} value={draft.membership_package_id} onChange={(event) => set("membership_package_id", event.target.value)}>
            <option value="">{t("noPackage")}</option>
            {packageOptions.map((pkg) => (
              <option key={String(pkg.id)} value={String(pkg.id)}>{String(pkg.name ?? pkg.code ?? pkg.id)}</option>
            ))}
          </select>
        </Field>

        {coachCandidates.length > 0 ? (
          <Field label={t("coaches")} group>
            <div className="flex flex-wrap gap-2">
              {coachCandidates.map((coach) => {
                const on = draft.coach_ids.includes(coach.id);
                return (
                  <button
                    key={coach.id}
                    type="button"
                    aria-pressed={on}
                    onClick={() => set("coach_ids", on ? draft.coach_ids.filter((c) => c !== coach.id) : [...draft.coach_ids, coach.id])}
                    className="rounded-full px-3 py-1.5 text-xs font-semibold"
                    style={{ background: on ? "var(--text)" : "var(--border)", color: on ? "var(--bg)" : "var(--text-soft)" }}
                  >
                    {coach.nickname ?? "?"}
                  </button>
                );
              })}
            </div>
          </Field>
        ) : null}

        <Field label={t("programme")} hint={t("programmeHint")} group>
          <div className="space-y-2">
            {draft.programme.map((row, index) => (
              <div key={index} className="flex gap-2">
                <select
                  aria-label={t("programmeDay")}
                  className="w-40 shrink-0 rounded-xl px-2 py-2 text-sm"
                  style={inputStyle}
                  disabled={locked}
                  value={row.day}
                  onChange={(event) => set("programme", draft.programme.map((r, i) => (i === index ? { ...r, day: Number(event.target.value) } : r)))}
                >
                  {Array.from({ length: weeks * 7 }, (_, day) => (
                    <option key={day} value={day}>
                      {draft.starts_on
                        ? t("dayOptionDate", { day: day + 1, date: seasonDate(locale, programmeDate(draft.starts_on, day)) })
                        : t("dayOption", { day: day + 1 })}
                    </option>
                  ))}
                </select>
                <select
                  aria-label={t("programmeWorkout")}
                  className="min-w-0 flex-1 rounded-xl px-2 py-2 text-sm"
                  style={inputStyle}
                  disabled={locked}
                  value={row.workout_id}
                  onChange={(event) => set("programme", draft.programme.map((r, i) => (i === index ? { ...r, workout_id: event.target.value } : r)))}
                >
                  <option value="">{t("pickWorkout")}</option>
                  {workoutOptions.map((workout) => (
                    <option key={workout.id} value={workout.id}>{workout.title}</option>
                  ))}
                </select>
                {!locked ? (
                  <button
                    type="button"
                    aria-label={t("removeRow")}
                    onClick={() => set("programme", draft.programme.filter((_, i) => i !== index))}
                    className="shrink-0 rounded-xl px-3 text-sm"
                    style={{ background: "var(--border)", color: "var(--text-soft)" }}
                  >
                    ×
                  </button>
                ) : null}
              </div>
            ))}
            {!locked ? (
              <button
                type="button"
                onClick={() => {
                  const last = draft.programme.at(-1)?.day ?? -1;
                  set("programme", [...draft.programme, { day: Math.min(weeks * 7 - 1, last + 1), workout_id: "" }]);
                }}
                className="rounded-full px-3 py-1.5 text-xs font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
              >
                {t("addWorkout")}
              </button>
            ) : null}
          </div>
        </Field>

        <Field label={t("fieldWelcome")} hint={t("fieldWelcomeHint")}>
          <textarea className={inputClass} style={inputStyle} rows={2} maxLength={2000} value={draft.welcome_message} onChange={(event) => set("welcome_message", event.target.value)} />
        </Field>
      </fieldset>

      {save.error ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t(seasonErrorKey(save.error))}</p> : null}

      {!closed ? (
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            disabled={!canSave}
            onClick={() => save.mutate(null)}
            className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--border)", color: "var(--text)" }}
          >
            {season ? t("save") : t("saveDraft")}
          </button>
          {status === "draft" ? (
            <button
              type="button"
              disabled={!canSave}
              onClick={() => save.mutate("published")}
              className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {t("publish")}
            </button>
          ) : null}
          {season ? (
            confirmingCancel ? (
              <button
                type="button"
                disabled={save.isPending}
                onClick={() => save.mutate("cancelled")}
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
              >
                {t("cancelSeasonConfirm")}
              </button>
            ) : (
              <button
                type="button"
                onClick={() => setConfirmingCancel(true)}
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ color: "var(--danger)" }}
              >
                {t("cancelSeason")}
              </button>
            )
          ) : null}
        </div>
      ) : null}

      {season ? <Enrollments season={season} token={token} onChanged={refresh} /> : null}
    </div>
  );
}

const ENROLLMENT_ORDER: StaffSeasonEnrollment["status"][] = ["requested", "waitlisted", "active", "completed", "declined", "cancelled"];

function Enrollments({
  season,
  token,
  onChanged,
}: {
  season: StaffSeasonDetail;
  token: string;
  onChanged: (saved?: StaffSeasonDetail) => Promise<void>;
}) {
  const t = useTranslations("Seasons");
  const [declining, setDeclining] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const enrollments = [...(season.enrollments ?? [])]
    .filter((enrollment) => enrollment?.id)
    .sort((a, b) => ENROLLMENT_ORDER.indexOf(a.status) - ENROLLMENT_ORDER.indexOf(b.status));

  const act = useMutation({
    mutationFn: ({ id, action }: { id: string; action: EnrollmentAction }) =>
      actOnSeasonEnrollment(token, id, action, action === "decline" ? reason : undefined),
    onSuccess: async (saved) => {
      setDeclining(null);
      setReason("");
      await onChanged(saved);
    },
  });

  return (
    <section className="space-y-3">
      <h3 className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
        {t("participants", { active: season.counts?.active ?? 0, capacity: season.capacity ?? 0 })}
      </h3>
      {enrollments.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noRequests")}</p>
      ) : (
        <ul className="overflow-hidden rounded-2xl" style={{ border: "1px solid var(--border)" }}>
          {enrollments.map((enrollment, index) => (
            <li key={enrollment.id} className="space-y-2 px-4 py-3" style={{ borderTop: index === 0 ? "none" : "1px solid var(--border)" }}>
              <div className="flex flex-wrap items-center gap-2">
                <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{enrollment.nickname ?? "?"}</span>
                <span className="text-xs font-semibold" style={{ color: statusTone(enrollment.status) }}>{t(`enrollment_${enrollment.status}`)}</span>
                {enrollment.status === "requested" ? (
                  <ActionButton primary disabled={act.isPending} onClick={() => act.mutate({ id: enrollment.id, action: "confirm" })}>
                    {t("confirm")}
                  </ActionButton>
                ) : null}
                {enrollment.status === "requested" || enrollment.status === "waitlisted" ? (
                  <ActionButton disabled={act.isPending} onClick={() => setDeclining(declining === enrollment.id ? null : enrollment.id)}>
                    {t("decline")}
                  </ActionButton>
                ) : null}
                {enrollment.status === "active" ? (
                  <ActionButton disabled={act.isPending} onClick={() => act.mutate({ id: enrollment.id, action: "remove" })}>
                    {t("remove")}
                  </ActionButton>
                ) : null}
              </div>
              {enrollment.status === "declined" && enrollment.decline_reason ? (
                <p className="text-xs italic" style={{ color: "var(--muted)" }}>{enrollment.decline_reason}</p>
              ) : null}
              {declining === enrollment.id ? (
                <div className="flex gap-2">
                  <input
                    className={inputClass}
                    style={inputStyle}
                    maxLength={300}
                    placeholder={t("declineReason")}
                    value={reason}
                    onChange={(event) => setReason(event.target.value)}
                  />
                  <ActionButton disabled={act.isPending} onClick={() => act.mutate({ id: enrollment.id, action: "decline" })}>
                    {t("declineSend")}
                  </ActionButton>
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      {act.error ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t(seasonErrorKey(act.error))}</p> : null}
    </section>
  );
}

function ActionButton({
  children,
  onClick,
  primary,
  disabled,
}: {
  children: ReactNode;
  onClick: () => void;
  primary?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="shrink-0 rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50"
      style={primary ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { background: "var(--border)", color: "var(--text-soft)" }}
    >
      {children}
    </button>
  );
}

function Field({ label, hint, group, children }: { label: string; hint?: string; group?: boolean; children: ReactNode }) {
  const body = (
    <>
      <span className="block text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
      {hint ? <span className="block text-xs" style={{ color: "var(--muted)" }}>{hint}</span> : null}
    </>
  );
  // A row of several controls is a group, not one label (a label would forward clicks to its first control).
  return group ? (
    <div role="group" aria-label={label} className="space-y-1.5">{body}</div>
  ) : (
    <label className="block space-y-1.5">{body}</label>
  );
}

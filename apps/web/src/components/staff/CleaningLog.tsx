"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  archiveCleaningArea,
  createCleaningArea,
  fetchCleaningAreas,
  fetchCleaningEntries,
  finishCleaning,
  startCleaning,
  type CleaningArea,
  type CleaningEntry,
} from "@/api/roles";
import { useSession } from "@/components/session-provider";
import { CLEANING_TODAY_KEY, CleaningSchedules, CleaningToday } from "@/components/spaces/CleaningToday";
import { CleaningPointsCarousel } from "@/components/spaces/CleaningPointsCarousel";
import { firstUnanswered, resultCounts, toPointResults, type PointAnswer } from "@/components/spaces/cleaning-points";
import { RoomPhotoStrip } from "@/components/spaces/RoomPhotoStrip";
import { formatDateTime } from "@/components/client/format";
import {
  StaffPanel,
  StatusText,
  captionClass,
  captionStyle,
  inputClass,
  inputStyle,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  dangerButtonStyle,
} from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

const AREAS_KEY = ["staff", "cleaning", "areas"] as const;
const ENTRIES_KEY = ["staff", "cleaning", "entries"] as const;

/** `/admin/cleaning`: what was cleaned, when and by whom (ADR-102); what is due today (ADR-202). */
export function CleaningLog() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const { membership } = useSelectedMembershipRole();
  const canRecord = can(membership, "record_cleaning");
  const canManage = can(membership, "manage_cleaning_areas");
  const canSchedule = can(membership, "manage_cleaning_schedule");

  const areas = useQuery({ queryKey: AREAS_KEY, enabled: Boolean(token), queryFn: () => fetchCleaningAreas(token!) });
  const entries = useQuery({ queryKey: ENTRIES_KEY, enabled: Boolean(token), queryFn: () => fetchCleaningEntries(token!) });
  const refresh = () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: AREAS_KEY }),
      queryClient.invalidateQueries({ queryKey: ENTRIES_KEY }),
      queryClient.invalidateQueries({ queryKey: CLEANING_TODAY_KEY }),
    ]);

  const start = useMutation({ mutationFn: (areaId: string) => startCleaning(token!, areaId), onSuccess: refresh });
  const archive = useMutation({ mutationFn: (areaId: string) => archiveCleaningArea(token!, areaId), onSuccess: refresh });

  const areaById = new Map((areas.data ?? []).map((area) => [area.id, area]));
  const open = (entries.data ?? []).filter((entry) => !entry.finished_at && entry.user_id === currentUser?.id);
  const finished = (entries.data ?? []).filter((entry) => entry.finished_at);
  const activeAreas = (areas.data ?? []).filter((area) => !area.archived_at);

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-5xl flex-col gap-6">
        <header>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{i18n("cleanEyebrow")}</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{i18n("cleanTitle")}</h1>
          <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>{i18n("cleanIntro")}</p>
        </header>

        {open.map((entry) => (
          <OpenCleaning key={entry.id} token={token!} entry={entry} area={areaById.get(entry.area_id)} onDone={refresh} />
        ))}

        {token ? <CleaningToday token={token} canRecord={canRecord} onStart={(areaId) => start.mutate(areaId)} /> : null}

        <StaffPanel labelledBy="cleaning-areas" title={i18n("cleanAreas")}>
          {areas.isPending ? (
            <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
          ) : activeAreas.length === 0 ? (
            <StatusText tone="muted">{i18n("cleanNoAreas")}</StatusText>
          ) : (
            <ul className="grid gap-3 sm:grid-cols-2">
              {activeAreas.map((area) => (
                <li key={area.id} className="flex flex-col gap-2 rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                  <p className="font-semibold" style={{ color: "var(--text)" }}>{area.name}</p>
                  <p className="text-xs" style={{ color: "var(--dim)" }}>
                    {area.last_cleaned_at
                      ? i18n("cleanLastCleaned", { when: formatDateTime(area.last_cleaned_at, locale) })
                      : i18n("cleanNeverCleaned")}
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {canRecord ? (
                      <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} disabled={start.isPending} onClick={() => start.mutate(area.id)}>
                        {i18n("cleanStart")}
                      </button>
                    ) : null}
                    {canManage ? (
                      <button
                        type="button"
                        className={secondaryButtonClass}
                        style={dangerButtonStyle}
                        disabled={archive.isPending}
                        onClick={() => {
                          if (window.confirm(i18n("cleanArchiveConfirm", { name: area.name }))) archive.mutate(area.id);
                        }}
                      >
                        {i18n("cleanArchive")}
                      </button>
                    ) : null}
                  </div>
                </li>
              ))}
            </ul>
          )}
          {start.isError ? <StatusText tone="error">{localizeError(start.error, i18n)}</StatusText> : null}
          {canManage && token ? <NewArea token={token} onDone={refresh} /> : null}
        </StaffPanel>

        {canSchedule && token ? <CleaningSchedules token={token} spaces={activeAreas} /> : null}

        <StaffPanel labelledBy="cleaning-history" title={i18n("cleanHistory")}>
          {entries.isPending ? (
            <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
          ) : finished.length === 0 ? (
            <StatusText tone="muted">{i18n("cleanNoHistory")}</StatusText>
          ) : (
            <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
              {finished.map((entry) => (
                <li key={entry.id} className="flex flex-col gap-1 py-3 text-sm">
                  <span className="font-semibold" style={{ color: "var(--text)" }}>
                    {areaById.get(entry.area_id)?.name ?? "—"}
                  </span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {formatDateTime(entry.started_at, locale)} → {formatDateTime(entry.finished_at, locale)}
                    {entry.nickname ? ` · ${entry.nickname}` : ""}
                  </span>
                  {entry.tasks_done.length > 0 ? (
                    <span className="text-xs" style={{ color: "var(--text-soft)" }}>✓ {entry.tasks_done.join(" · ")}</span>
                  ) : null}
                  {entry.note ? <span className="text-xs" style={{ color: "var(--muted)" }}>{entry.note}</span> : null}
                  <PointResults results={entry.point_results} />
                </li>
              ))}
            </ul>
          )}
        </StaffPanel>
      </div>
    </main>
  );
}

function OpenCleaning({ token, entry, area, onDone }: { token: string; entry: CleaningEntry; area?: CleaningArea; onDone: () => Promise<unknown> }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const [done, setDone] = useState<string[]>([]);
  const [note, setNote] = useState("");
  const [answers, setAnswers] = useState<Record<string, PointAnswer>>({});
  const spaceT = useTranslations("Spaces");
  const points = area?.points ?? [];
  const pending = firstUnanswered(points, answers);
  const finish = useMutation({
    mutationFn: () =>
      finishCleaning(token, entry.id, {
        tasks_done: done,
        note: note.trim() || null,
        ...(points.length > 0 ? { point_results: toPointResults(points, answers) } : {}),
      }),
    onSuccess: onDone,
  });

  return (
    <StaffPanel labelledBy={`cleaning-${entry.id}`} eyebrow={i18n("cleanInProgress")} title={area?.name ?? "—"}>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("cleanStartedAt", { when: formatDateTime(entry.started_at, locale) })}</p>
      {(area?.tasks ?? []).length > 0 ? (
        <fieldset className="mt-3 flex flex-col gap-2">
          <legend className={captionClass} style={captionStyle}>{i18n("cleanTasks")}</legend>
          {area!.tasks.map((task) => (
            <label key={task} className="flex items-center gap-3 text-sm" style={{ color: "var(--text-soft)" }}>
              <input
                type="checkbox"
                checked={done.includes(task)}
                onChange={() => setDone((current) => (current.includes(task) ? current.filter((item) => item !== task) : [...current, task]))}
              />
              {task}
            </label>
          ))}
        </fieldset>
      ) : null}
      {points.length > 0 ? (
        <div className="mt-3">
          <p className={captionClass} style={captionStyle}>{spaceT("cleaningPoints")}</p>
          <div className="mt-2">
            <CleaningPointsCarousel
              token={token}
              points={points}
              answers={answers}
              onChange={(pointId, answer) => setAnswers((current) => ({ ...current, [pointId]: answer }))}
            />
          </div>
        </div>
      ) : null}
      <label className="mt-3 block">
        <span className={captionClass} style={captionStyle}>{i18n("cleanNote")}</span>
        <textarea className={inputClass} style={inputStyle} rows={2} maxLength={1000} value={note} onChange={(event) => setNote(event.target.value)} />
      </label>
      <button type="button" className={`mt-3 ${primaryButtonClass}`} style={primaryButtonStyle} disabled={finish.isPending || pending >= 0} data-testid="cleaning-finish" onClick={() => finish.mutate()}>
        {i18n("cleanFinish")}
      </button>
      {pending >= 0 ? (
        <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{spaceT("cleaningPointsLeft", { count: points.length - points.filter((point) => answers[point.id]?.status).length })}</p>
      ) : null}
      {finish.isError ? <StatusText tone="error">{localizeError(finish.error, i18n)}</StatusText> : null}
    </StaffPanel>
  );
}

/** ADR-290: what the janitor answered for each cleaning point. */
function PointResults({ results }: { results?: CleaningEntry["point_results"] }) {
  const t = useTranslations("Spaces");
  if (!results || results.length === 0) return null;
  const { cleaned, notCleaned } = resultCounts(results);
  const afterPhotos = results.filter((result) => result.after_url).map((result) => ({ id: result.point_id, url: result.after_url, caption: result.instruction }));
  return (
    <div className="flex flex-col gap-1" data-testid="cleaning-point-results">
      <span className="text-xs" style={{ color: notCleaned > 0 ? "var(--danger)" : "var(--text-soft)" }}>
        {[cleaned > 0 ? t("cleaningPointsCleaned", { count: cleaned }) : null, notCleaned > 0 ? t("cleaningPointsNotCleaned", { count: notCleaned }) : null]
          .filter(Boolean)
          .join(" · ")}
      </span>
      {results
        .filter((result) => result.status === "not_cleaned")
        .map((result) => (
          <span key={result.point_id} className="text-xs" style={{ color: "var(--muted)" }}>
            ✕ {result.instruction}: {result.note}
          </span>
        ))}
      {afterPhotos.length > 0 ? <RoomPhotoStrip photos={afterPhotos} /> : null}
    </div>
  );
}

function NewArea({ token, onDone }: { token: string; onDone: () => Promise<unknown> }) {
  const i18n = useUiTranslations();
  const [name, setName] = useState("");
  const [tasks, setTasks] = useState("");
  const create = useMutation({
    mutationFn: () =>
      createCleaningArea(token, {
        name: name.trim(),
        tasks: tasks.split("\n").map((task) => task.trim()).filter(Boolean),
      }),
    onSuccess: async () => {
      setName("");
      setTasks("");
      await onDone();
    },
  });

  return (
    <form
      className="mt-5 grid gap-3 border-t pt-5 sm:grid-cols-2"
      style={{ borderColor: "var(--border)" }}
      onSubmit={(event) => {
        event.preventDefault();
        if (name.trim()) create.mutate();
      }}
    >
      <label className="block">
        <span className={captionClass} style={captionStyle}>{i18n("cleanAreaName")}</span>
        <input className={inputClass} style={inputStyle} maxLength={80} value={name} onChange={(event) => setName(event.target.value)} />
      </label>
      <label className="block">
        <span className={captionClass} style={captionStyle}>{i18n("cleanAreaTasks")}</span>
        <textarea className={inputClass} style={inputStyle} rows={3} value={tasks} onChange={(event) => setTasks(event.target.value)} />
      </label>
      <div className="sm:col-span-2">
        <button type="submit" className={primaryButtonClass} style={primaryButtonStyle} disabled={!name.trim() || create.isPending}>
          {i18n("cleanAddArea")}
        </button>
        {create.isError ? <StatusText tone="error">{localizeError(create.error, i18n)}</StatusText> : null}
      </div>
    </form>
  );
}

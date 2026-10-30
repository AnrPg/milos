"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  CLASS_AUDIENCES,
  CLASS_LEVELS,
  archiveClassType,
  createClassType,
  listAdminClassTypes,
  updateClassType,
  type ClassLevel,
  type ClassTypePayload,
  type ClassTypeRecord,
} from "@/api/schedule";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

type ArchiveMapping = {
  source: ClassTypeRecord;
  futureCount: number;
  replacementId: string;
};

export function ClassTypeSettings({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [newName, setNewName] = useState("");
  const [editing, setEditing] = useState<ClassTypeRecord | null>(null);
  const [editName, setEditName] = useState("");
  const [archiveMapping, setArchiveMapping] = useState<ArchiveMapping | null>(null);
  const [error, setError] = useState<string | null>(null);

  const query = useQuery({
    queryKey: ["admin", "class-types"],
    queryFn: () => listAdminClassTypes(token),
  });

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ["admin", "class-types"] });
  };

  const createMutation = useMutation({
    mutationFn: () => createClassType(token, { name: newName.trim() }),
    onSuccess: async () => {
      setNewName("");
      setError(null);
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? localizeError(cause, i18n) : i18n("couldNotCreateClassTyped413603")),
  });

  const updateMutation = useMutation({
    mutationFn: () => {
      if (!editing) throw new Error(i18n("chooseAClassTypeToEdit268bb46"));
      return updateClassType(token, editing.id, { name: editName.trim(), sort_order: editing.sort_order });
    },
    onSuccess: async () => {
      setEditing(null);
      setEditName("");
      setError(null);
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? localizeError(cause, i18n) : i18n("couldNotUpdateClassType039b007")),
  });

  // ADR-097: visits one booking uses, and whether bookings count as events.
  const ruleMutation = useMutation({
    mutationFn: ({ type, patch }: { type: ClassTypeRecord; patch: ClassTypeRulePatch }) =>
      updateClassType(token, type.id, { name: type.name, sort_order: type.sort_order, ...patch }),
    onSuccess: async () => {
      setError(null);
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? localizeError(cause, i18n) : i18n("couldNotUpdateClassType039b007")),
  });

  const archiveMutation = useMutation({
    mutationFn: async ({ source, replacementId }: { source: ClassTypeRecord; replacementId?: string }) => {
      try {
        return await archiveClassType(token, source.id, replacementId);
      } catch (cause) {
        if (cause instanceof ApiError && cause.status === 409 && !replacementId) {
          setError(null);
          setArchiveMapping({
            source,
            futureCount: cause.payload.future_class_count ?? 0,
            replacementId: "",
          });
          return null;
        }
        throw cause;
      }
    },
    onSuccess: async (result) => {
      if (!result) return;
      setArchiveMapping(null);
      setError(null);
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? localizeError(cause, i18n) : i18n("couldNotArchiveClassType0cf6334")),
  });

  const allTypes = query.data ?? [];
  const activeTypes = allTypes.filter((type) => !type.archived_at);
  const archivedTypes = allTypes.filter((type) => type.archived_at);

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-3 sm:flex-row">
        <input
          className="min-w-0 flex-1 rounded-2xl px-4 py-3 text-sm outline-none"
          onChange={(event) => setNewName(event.target.value)}
          placeholder={i18n("newClassTypeName6a25273")}
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          value={newName}
        />
        <button
          className="rounded-full px-5 py-3 text-sm font-semibold disabled:opacity-50"
          disabled={createMutation.isPending || newName.trim().length < 2}
          onClick={() => createMutation.mutate()}
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          type="button"
        >
          {createMutation.isPending ? i18n("addingffb2e62") : i18n("addClassType6446375")}
        </button>
      </div>

      {query.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loadingClassTypesacb2cdf")}</p> : null}

      {activeTypes.length > 0 ? <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{i18n("admClassTypeRulesHint")}</p> : null}

      <div className="space-y-2">
        {activeTypes.map((type) => (
          <div
            className="flex flex-col gap-3 rounded-[1.3rem] p-4 sm:flex-row sm:items-center"
            key={type.id}
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            {editing?.id === type.id ? (
              <input
                autoFocus
                className="min-w-0 flex-1 rounded-xl px-3 py-2 text-sm outline-none"
                onChange={(event) => setEditName(event.target.value)}
                style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={editName}
              />
            ) : (
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{type.name}</p>
                <ClassTypeRules
                  type={type}
                  disabled={ruleMutation.isPending}
                  onChange={(patch) => ruleMutation.mutate({ type, patch })}
                />
              </div>
            )}

            <div className="flex gap-2">
              {editing?.id === type.id ? (
                <>
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50"
                    disabled={updateMutation.isPending || editName.trim().length < 2}
                    onClick={() => updateMutation.mutate()}
                    style={{ background: "var(--text)", color: "var(--bg)" }}
                    type="button"
                  >
                    {i18n("saveefc007a")}
                  </button>
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold"
                    onClick={() => setEditing(null)}
                    style={{ background: "var(--border)", color: "var(--muted)" }}
                    type="button"
                  >
                    {i18n("cancel77dfd21")}
                  </button>
                </>
              ) : (
                <>
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold"
                    onClick={() => { setEditing(type); setEditName(type.name); }}
                    style={{ background: "var(--border)", color: "var(--text-soft)" }}
                    type="button"
                  >
                    {i18n("renamed3f4cb8")}
                  </button>
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50"
                    disabled={archiveMutation.isPending || activeTypes.length < 2}
                    onClick={() => archiveMutation.mutate({ source: type })}
                    style={{ background: "color-mix(in srgb, var(--danger) 12%, transparent)", color: "var(--danger)" }}
                    type="button"
                  >
                    {i18n("removee963907")}
                  </button>
                </>
              )}
            </div>
          </div>
        ))}
      </div>

      {archivedTypes.length > 0 ? (
        <details className="rounded-[1.3rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <summary className="cursor-pointer text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {i18n("archivedClassTypes8e68083")}{archivedTypes.length})
          </summary>
          <div className="mt-3 space-y-2">
            {archivedTypes.map((type) => (
              <div className="flex items-center justify-between gap-3 text-sm" key={type.id}>
                <span style={{ color: "var(--dim)" }}>{type.name}</span>
                <span className="text-xs" style={{ color: "var(--border-strong)" }}>{i18n("historicalOnly95b4b26")}</span>
              </div>
            ))}
          </div>
        </details>
      ) : null}

      {/* ADR-214: while the mapping dialog is open, its errors show inside it. */}
      {error && !archiveMapping ? <ErrorNotice>{error}</ErrorNotice> : null}

      {archiveMapping ? (
        <Dialog
          onClose={() => setArchiveMapping(null)}
          error={error}
          eyebrow={<span style={{ color: "var(--danger)" }}>{i18n("replacementRequireda658534")}</span>}
          title={i18n("mapFutureClassesBeforeRemoval544f152")}
          size="lg"
          variant="center"
          footer={
            <div className="w-full flex justify-end gap-3">
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold"
                onClick={() => setArchiveMapping(null)}
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                type="button"
              >
                {i18n("cancel77dfd21")}
              </button>
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
                disabled={!archiveMapping.replacementId || archiveMutation.isPending}
                onClick={() => archiveMutation.mutate({ source: archiveMapping.source, replacementId: archiveMapping.replacementId })}
                style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
                type="button"
              >
                {archiveMutation.isPending ? i18n("mapping2712740") : i18n("mapAndRemove79dd58a")}
              </button>
            </div>
          }
        >
            <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
              {i18n("classTypeArchiveFutureUse", { count: archiveMapping.futureCount, name: archiveMapping.source.name })}
            </p>
            <Select
              className="mt-5 w-full rounded-2xl px-4 py-3 text-sm outline-none"
              onValueChange={(value) => setArchiveMapping((current) => current ? { ...current, replacementId: value } : current)}
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={archiveMapping.replacementId}
            >
              <option value="">{i18n("chooseReplacementClassType8eef42c")}</option>
              {activeTypes.filter((type) => type.id !== archiveMapping.source.id).map((type) => (
                <option key={type.id} value={type.id}>{type.name}</option>
              ))}
            </Select>
        </Dialog>
      ) : null}
    </div>
  );
}

type ClassTypeRulePatch = Pick<ClassTypePayload, "credit_cost" | "kind" | "level" | "audiences">;

function ClassTypeRules({
  type,
  disabled,
  onChange,
}: {
  type: ClassTypeRecord;
  disabled: boolean;
  onChange: (patch: ClassTypeRulePatch) => void;
}) {
  const i18n = useUiTranslations();
  const t = useTranslations("BoxSchedule");
  const cost = type.credit_cost ?? 1;
  const audiences = type.audiences ?? [];
  const adv = useTranslations("AdvancedSettings");
  const [open, setOpen] = useState(false);
  const stepStyle = { background: "var(--border)", color: "var(--text-soft)" };

  return (
    <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-2 text-xs" style={{ color: "var(--muted)" }}>
      <label className="flex items-center gap-2">
        <input
          checked={type.kind === "event"}
          disabled={disabled}
          onChange={(event) => onChange({ kind: event.target.checked ? "event" : "class" })}
          type="checkbox"
        />
        {i18n("admClassTypeEvent")}
      </label>
      {/* ADR-255: visits per booking, level and audience have a good default, so they sit under «Προχωρημένα». */}
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className="font-semibold"
        style={{ color: "var(--primary-strong)" }}
      >
        {adv("title")} {open ? "▴" : "▾"}
      </button>
      {open ? (
      <>
      <span className="flex items-center gap-2">
        {i18n("admVisitsPerBooking")}
        <button
          aria-label={i18n("admDecrease")}
          className="h-6 w-6 rounded-full font-semibold disabled:opacity-40"
          disabled={disabled || cost <= 1}
          onClick={() => onChange({ credit_cost: cost - 1 })}
          style={stepStyle}
          type="button"
        >
          −
        </button>
        <span className="w-4 text-center font-semibold tabular-nums" style={{ color: "var(--text)" }}>{cost}</span>
        <button
          aria-label={i18n("admIncrease")}
          className="h-6 w-6 rounded-full font-semibold disabled:opacity-40"
          disabled={disabled || cost >= 10}
          onClick={() => onChange({ credit_cost: cost + 1 })}
          style={stepStyle}
          type="button"
        >
          +
        </button>
      </span>
      {/* Plan §5a decision 2: members filter Πρόγραμμα by these two tags. */}
      <label className="flex items-center gap-2">
        {t("chipLevel")}
        <Select
          value={type.level ?? "all_levels"}
          disabled={disabled}
          onValueChange={(value) => onChange({ level: value as ClassLevel })}
          className="rounded-lg px-2 py-1 text-xs font-semibold"
          style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {CLASS_LEVELS.map((level) => (
            <option key={level} value={level}>
              {t(`level_${level}`)}
            </option>
          ))}
        </Select>
      </label>
      <span className="flex flex-wrap items-center gap-1.5" role="group" aria-label={t("audience")}>
        {t("audience")}
        {audiences.length === 0 ? (
          <span className="font-semibold" style={{ color: "var(--text)" }}>
            {t("audienceEveryone")}
          </span>
        ) : null}
        {CLASS_AUDIENCES.map((audience) => {
          const on = audiences.includes(audience);
          return (
            <button
              key={audience}
              type="button"
              aria-pressed={on}
              disabled={disabled}
              onClick={() =>
                onChange({
                  audiences: on ? audiences.filter((value) => value !== audience) : [...audiences, audience],
                })
              }
              className="rounded-full px-2.5 py-0.5 font-semibold disabled:opacity-50"
              style={{
                background: on ? "color-mix(in srgb, var(--primary) 18%, transparent)" : "var(--border)",
                color: on ? "var(--primary-strong)" : "var(--text-soft)",
              }}
            >
              {t(`audience_${audience}`)}
            </button>
          );
        })}
      </span>
      </>
      ) : null}
    </div>
  );
}

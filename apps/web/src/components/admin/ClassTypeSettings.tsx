"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { ApiError } from "@/api/client";
import {
  archiveClassType,
  createClassType,
  listAdminClassTypes,
  updateClassType,
  type ClassTypeRecord,
} from "@/api/schedule";

type ArchiveMapping = {
  source: ClassTypeRecord;
  futureCount: number;
  replacementId: string;
};

export function ClassTypeSettings({ token }: { token: string }) {
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
    onError: (cause) => setError(cause instanceof Error ? cause.message : "Could not create class type."),
  });

  const updateMutation = useMutation({
    mutationFn: () => {
      if (!editing) throw new Error("Choose a class type to edit.");
      return updateClassType(token, editing.id, { name: editName.trim(), sort_order: editing.sort_order });
    },
    onSuccess: async () => {
      setEditing(null);
      setEditName("");
      setError(null);
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? cause.message : "Could not update class type."),
  });

  const archiveMutation = useMutation({
    mutationFn: async ({ source, replacementId }: { source: ClassTypeRecord; replacementId?: string }) => {
      try {
        return await archiveClassType(token, source.id, replacementId);
      } catch (cause) {
        if (cause instanceof ApiError && cause.status === 409 && !replacementId) {
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
    onError: (cause) => setError(cause instanceof Error ? cause.message : "Could not archive class type."),
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
          placeholder="New class type name"
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
          {createMutation.isPending ? "Adding…" : "+ Add class type"}
        </button>
      </div>

      {query.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>Loading class types…</p> : null}

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
                <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{type.slug}</p>
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
                    Save
                  </button>
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold"
                    onClick={() => setEditing(null)}
                    style={{ background: "var(--border)", color: "var(--muted)" }}
                    type="button"
                  >
                    Cancel
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
                    Rename
                  </button>
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50"
                    disabled={archiveMutation.isPending || activeTypes.length < 2}
                    onClick={() => archiveMutation.mutate({ source: type })}
                    style={{ background: "color-mix(in srgb, var(--danger) 12%, transparent)", color: "var(--danger)" }}
                    type="button"
                  >
                    Remove
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
            Archived class types ({archivedTypes.length})
          </summary>
          <div className="mt-3 space-y-2">
            {archivedTypes.map((type) => (
              <div className="flex items-center justify-between gap-3 text-sm" key={type.id}>
                <span style={{ color: "var(--dim)" }}>{type.name}</span>
                <span className="text-xs" style={{ color: "var(--border-strong)" }}>Historical only</span>
              </div>
            ))}
          </div>
        </details>
      ) : null}

      {error ? <p className="text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}

      {archiveMapping ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: "rgba(0,0,0,0.68)" }}>
          <div className="w-full max-w-lg rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border-strong)" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--danger)" }}>Replacement required</p>
            <h3 className="mt-2 text-xl font-semibold" style={{ color: "var(--text)" }}>Map future classes before removal</h3>
            <p className="mt-3 text-sm leading-6" style={{ color: "var(--muted)" }}>
              {archiveMapping.futureCount} future class{archiveMapping.futureCount === 1 ? "" : "es"} use {archiveMapping.source.name}. Past and current classes will retain it for history and analytics.
            </p>
            <select
              className="mt-5 w-full rounded-2xl px-4 py-3 text-sm outline-none"
              onChange={(event) => setArchiveMapping((current) => current ? { ...current, replacementId: event.target.value } : current)}
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={archiveMapping.replacementId}
            >
              <option value="">Choose replacement class type</option>
              {activeTypes.filter((type) => type.id !== archiveMapping.source.id).map((type) => (
                <option key={type.id} value={type.id}>{type.name}</option>
              ))}
            </select>
            <div className="mt-6 flex justify-end gap-3">
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold"
                onClick={() => setArchiveMapping(null)}
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                type="button"
              >
                Cancel
              </button>
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
                disabled={!archiveMapping.replacementId || archiveMutation.isPending}
                onClick={() => archiveMutation.mutate({ source: archiveMapping.source, replacementId: archiveMapping.replacementId })}
                style={{ background: "var(--danger)", color: "white" }}
                type="button"
              >
                {archiveMutation.isPending ? "Mapping…" : "Map and remove"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { ApiError } from "@/api/client";
import {
  archiveLocation,
  createLocation,
  listAdminLocations,
  updateLocation,
  type FacilityLocation,
} from "@/api/facility";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const fieldStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

/** Gym locations (ADR-097). Optional: single-site gyms never need one. */
export function LocationSettings({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState({ name: "", address: "" });
  const [editing, setEditing] = useState<{ id: string; name: string; address: string } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const query = useQuery({
    queryKey: ["admin", "locations"],
    queryFn: () => listAdminLocations(token),
  });

  const refresh = async () => {
    setError(null);
    await queryClient.invalidateQueries({ queryKey: ["admin", "locations"] });
  };

  // Names are unique per gym; the API answers a duplicate with a changeset error on `name`.
  const fail = (cause: unknown) =>
    setError(
      cause instanceof ApiError && cause.status === 422 && cause.payload.errors?.name
        ? i18n("admLocationNameTaken")
        : localizeError(cause, i18n),
    );

  const createMutation = useMutation({
    mutationFn: () => createLocation(token, { name: draft.name.trim(), address: draft.address.trim() || null }),
    onSuccess: async () => {
      setDraft({ name: "", address: "" });
      await refresh();
    },
    onError: fail,
  });

  const updateMutation = useMutation({
    mutationFn: (target: { id: string; name: string; address: string }) =>
      updateLocation(token, target.id, { name: target.name.trim(), address: target.address.trim() || null }),
    onSuccess: async () => {
      setEditing(null);
      await refresh();
    },
    onError: fail,
  });

  const archiveMutation = useMutation({
    mutationFn: (location: FacilityLocation) => archiveLocation(token, location.id),
    onSuccess: refresh,
    onError: fail,
  });

  const all = query.data ?? [];
  const active = all.filter((location) => !location.archived_at);
  const archived = all.filter((location) => location.archived_at);

  return (
    <div className="space-y-5">
      {query.isSuccess && active.length === 0 ? (
        <p className="max-w-2xl text-sm leading-6" style={{ color: "var(--muted)" }}>{i18n("admLocationsEmpty")}</p>
      ) : null}

      <form
        className="flex flex-col gap-3 sm:flex-row"
        onSubmit={(event) => {
          event.preventDefault();
          createMutation.mutate();
        }}
      >
        <input
          aria-label={i18n("admLocationName")}
          className="min-w-0 flex-1 rounded-2xl px-4 py-3 text-sm outline-none"
          maxLength={80}
          onChange={(event) => setDraft({ ...draft, name: event.target.value })}
          placeholder={i18n("admLocationName")}
          style={fieldStyle}
          value={draft.name}
        />
        <input
          aria-label={i18n("admLocationAddressOptional")}
          className="min-w-0 flex-1 rounded-2xl px-4 py-3 text-sm outline-none"
          maxLength={200}
          onChange={(event) => setDraft({ ...draft, address: event.target.value })}
          placeholder={i18n("admLocationAddressOptional")}
          style={fieldStyle}
          value={draft.address}
        />
        <button
          className="rounded-full px-5 py-3 text-sm font-semibold disabled:opacity-50"
          disabled={createMutation.isPending || draft.name.trim().length < 2}
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          type="submit"
        >
          {createMutation.isPending ? i18n("addingffb2e62") : i18n("admLocationAdd")}
        </button>
      </form>

      {query.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p> : null}

      <div className="space-y-2">
        {active.map((location) => (
          <div
            className="flex flex-col gap-3 rounded-[1.3rem] p-4 sm:flex-row sm:items-center"
            key={location.id}
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            {editing?.id === location.id ? (
              <div className="flex min-w-0 flex-1 flex-col gap-2 sm:flex-row">
                <input
                  aria-label={i18n("admLocationName")}
                  autoFocus
                  className="min-w-0 flex-1 rounded-xl px-3 py-2 text-sm outline-none"
                  maxLength={80}
                  onChange={(event) => setEditing({ ...editing, name: event.target.value })}
                  style={{ ...fieldStyle, background: "var(--bg)" }}
                  value={editing.name}
                />
                <input
                  aria-label={i18n("admLocationAddressOptional")}
                  className="min-w-0 flex-1 rounded-xl px-3 py-2 text-sm outline-none"
                  maxLength={200}
                  onChange={(event) => setEditing({ ...editing, address: event.target.value })}
                  placeholder={i18n("admLocationAddressOptional")}
                  style={{ ...fieldStyle, background: "var(--bg)" }}
                  value={editing.address}
                />
              </div>
            ) : (
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{location.name}</p>
                {location.address ? <p className="mt-1 truncate text-xs" style={{ color: "var(--dim)" }}>{location.address}</p> : null}
              </div>
            )}

            <div className="flex gap-2">
              {editing?.id === location.id ? (
                <>
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50"
                    disabled={updateMutation.isPending || editing.name.trim().length < 2}
                    onClick={() => updateMutation.mutate(editing)}
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
                    onClick={() => setEditing({ id: location.id, name: location.name, address: location.address ?? "" })}
                    style={{ background: "var(--border)", color: "var(--text-soft)" }}
                    type="button"
                  >
                    {i18n("admLocationEdit")}
                  </button>
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50"
                    disabled={archiveMutation.isPending}
                    onClick={() => {
                      if (window.confirm(i18n("admLocationArchiveConfirm", { name: location.name }))) archiveMutation.mutate(location);
                    }}
                    style={{ background: "color-mix(in srgb, var(--danger) 12%, transparent)", color: "var(--danger)" }}
                    type="button"
                  >
                    {i18n("admLocationArchive")}
                  </button>
                </>
              )}
            </div>
          </div>
        ))}
      </div>

      {archived.length > 0 ? (
        <details className="rounded-[1.3rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <summary className="cursor-pointer text-sm font-semibold" style={{ color: "var(--muted)" }}>
            {i18n("admLocationsArchived", { count: archived.length })}
          </summary>
          <div className="mt-3 space-y-2">
            {archived.map((location) => (
              <div className="flex items-center justify-between gap-3 text-sm" key={location.id}>
                <span style={{ color: "var(--dim)" }}>{location.name}</span>
                <span className="text-xs" style={{ color: "var(--border-strong)" }}>{i18n("historicalOnly95b4b26")}</span>
              </div>
            ))}
          </div>
        </details>
      ) : null}

      {error ? <p className="text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </div>
  );
}

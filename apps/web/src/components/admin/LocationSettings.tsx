"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { ApiError } from "@/api/client";
import {
  archiveLocation,
  createLocation,
  listAdminLocations,
  type FacilityLocation,
} from "@/api/facility";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

const fieldStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

/**
 * Gym locations (ADR-097). Optional: single-site gyms never need one. Each
 * location is edited on its own page with its map pin and hours (ADR-141).
 */
export function LocationSettings({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const t = useTranslations("AdminLocation");
  const router = useRouter();
  const organizationSlug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [name, setName] = useState("");
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

  const editorHref = (id: string) => adminHref(`/admin/settings/locations/${id}`, organizationSlug);

  // A new location opens straight on its page, where the pin and hours are set.
  const createMutation = useMutation({
    mutationFn: () => createLocation(token, { name: name.trim() }),
    onSuccess: async (location) => {
      setName("");
      await refresh();
      router.push(editorHref(location.id));
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
          onChange={(event) => setName(event.target.value)}
          placeholder={i18n("admLocationName")}
          style={fieldStyle}
          value={name}
        />

        <button
          className="rounded-full px-5 py-3 text-sm font-semibold disabled:opacity-50"
          disabled={createMutation.isPending || name.trim().length < 2}
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
            <Link href={editorHref(location.id)} className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{location.name}</p>
              <p className="mt-1 truncate text-xs" style={{ color: "var(--dim)" }}>
                {[location.address, location.neighbourhood].filter(Boolean).join(" · ") || t("noAddress")}
              </p>
              {location.latitude == null ? (
                <p className="mt-1 text-xs font-semibold" style={{ color: "var(--warning)" }}>{t("noPinShort")}</p>
              ) : null}
            </Link>

            <div className="flex gap-2">
              <Link
                href={editorHref(location.id)}
                className="rounded-full px-4 py-2 text-xs font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
              >
                {i18n("admLocationEdit")}
              </Link>
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

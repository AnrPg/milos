"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { listTagSuggestions, resolveTagSuggestion, type TagSuggestion } from "@/api/public-profile";
import { useSession } from "@/components/session-provider";

/**
 * Platform review of tags gym owners could not find (board 3b Q5). «Added»
 * records that the tag joined the canonical list in code; nothing here edits
 * the lists themselves, so every gym keeps seeing the same vocabulary.
 */
export function PlatformTagSuggestions() {
  const t = useTranslations("PlatformTagSuggestions");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const suggestions = useQuery({
    queryKey: ["platform", "tag-suggestions"],
    queryFn: () => listTagSuggestions(token!),
    enabled: Boolean(token),
  });
  const resolve = useMutation({
    mutationFn: ({ id, status }: { id: string; status: "added" | "declined" }) => resolveTagSuggestion(token!, id, status),
    onSuccess: (_result, { id }) =>
      queryClient.setQueryData<TagSuggestion[]>(["platform", "tag-suggestions"], (current) =>
        (current ?? []).filter((suggestion) => suggestion.id !== id),
      ),
  });
  const forbidden = suggestions.error instanceof ApiError && suggestions.error.status === 403;
  const inList = (list: TagSuggestion["list"]) => (suggestions.data ?? []).filter((suggestion) => suggestion.list === list);

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <Link href="/platform/organizations" className="text-sm text-[var(--text-soft)]">
          ‹ {t("back")}
        </Link>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("subtitle")}</p>
      </header>

      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {suggestions.isError && !forbidden ? <p className="mt-6 text-[var(--danger)]">{t("loadError")}</p> : null}
      {suggestions.isPending && token ? <p className="mt-6 text-sm text-[var(--dim)]">{t("loading")}</p> : null}
      {suggestions.data?.length === 0 ? <p className="mt-6 text-[var(--text-soft)]">{t("empty")}</p> : null}
      {resolve.isError ? <p className="mt-6 text-[var(--danger)]">{t("resolveError")}</p> : null}

      {(["disciplines", "services", "audiences", "amenities"] as const).map((list) =>
        inList(list).length ? (
          <section key={list} className="mt-6 flex flex-col gap-2" aria-label={t(`list_${list}`)}>
            <h2 className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t(`list_${list}`)}</h2>
            <ul className="flex flex-col divide-y divide-[var(--border)] border-y border-[var(--border)]">
              {inList(list).map((suggestion) => (
                <li key={suggestion.id} className="flex flex-wrap items-center gap-3 py-3">
                  <div className="mr-auto flex flex-col">
                    <span className="font-semibold text-[var(--text)]">{suggestion.name}</span>
                    <span className="text-sm text-[var(--text-soft)]">
                      {suggestion.organization_name}
                      {suggestion.inserted_at
                        ? ` · ${new Date(suggestion.inserted_at).toLocaleDateString(locale, { day: "numeric", month: "short" })}`
                        : ""}
                    </span>
                  </div>
                  <button
                    type="button"
                    disabled={resolve.isPending}
                    aria-label={t("declineNamed", { name: suggestion.name })}
                    onClick={() => resolve.mutate({ id: suggestion.id, status: "declined" })}
                    className="rounded-full border border-[var(--border)] px-4 py-2 text-sm font-semibold text-[var(--text-soft)] disabled:opacity-40"
                  >
                    {t("decline")}
                  </button>
                  <button
                    type="button"
                    disabled={resolve.isPending}
                    aria-label={t("addedNamed", { name: suggestion.name })}
                    onClick={() => resolve.mutate({ id: suggestion.id, status: "added" })}
                    className="rounded-full bg-[var(--accent)] px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
                  >
                    {t("added")}
                  </button>
                </li>
              ))}
            </ul>
          </section>
        ) : null,
      )}
    </main>
  );
}

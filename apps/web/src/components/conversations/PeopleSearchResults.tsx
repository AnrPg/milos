"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { peopleSearchKey, searchPeople } from "@/api/conversations";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";

import { BuddyBadge } from "./ConversationRow";
import { personLabel } from "./conversation-model";
import { useConversationsToken, useOpenConversation } from "./use-conversations";

export const PEOPLE_SEARCH_MIN_QUERY = 2;

/**
 * «Search or start a conversation» (ADR-193 §4): people across Palee by name
 * or @handle; picking one opens (or finds) your conversation with them. The
 * inbox (ADR-196) owns the search box and passes the debounced `term`;
 * `excludeIds` leaves out people it already lists.
 */
export function PeopleSearchResults({
  term,
  excludeIds,
  onOpened,
}: {
  term: string;
  excludeIds?: ReadonlySet<string>;
  onOpened?: () => void;
}) {
  const t = useTranslations("Conversations");
  const tUi = useUiTranslations();
  const token = useConversationsToken();
  const open = useOpenConversation(onOpened);
  const searching = term.length >= PEOPLE_SEARCH_MIN_QUERY;
  const results = useQuery({
    queryKey: peopleSearchKey(term),
    enabled: Boolean(token) && searching,
    queryFn: ({ signal }) => searchPeople(token!, term, signal),
    staleTime: 30_000,
  });
  if (!searching) return null;
  const people = (results.data ?? []).filter((person) => !excludeIds?.has(person.id));

  return (
    <div className="flex flex-col gap-2" data-testid="people-search-results">
      {open.error ? (
        <p className="px-1 text-sm" role="alert" style={{ color: "var(--danger)" }}>
          {localizeError(open.error, tUi)}
        </p>
      ) : null}
      {results.isPending ? (
        <p className="px-1 text-sm" role="status" style={{ color: "var(--dim)" }}>
          {t("loading")}
        </p>
      ) : results.isError ? (
        <p className="px-1 text-sm" role="alert" style={{ color: "var(--danger)" }}>
          {localizeError(results.error, tUi)}
        </p>
      ) : people.length === 0 ? (
        <p className="px-1 py-2 text-sm" style={{ color: "var(--dim)" }}>
          {t("searchEmpty")}
        </p>
      ) : (
        <ul className="flex flex-col gap-2">
          {people.map((person) => {
            const name = personLabel(person, t("someone"));
            return (
              <li key={person.id}>
                <button
                  type="button"
                  disabled={open.isPending}
                  onClick={() => open.mutate(person.id)}
                  className="flex min-h-14 w-full items-center gap-3 rounded-2xl px-3 py-2 text-start outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)] disabled:opacity-60"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                  aria-label={t("messageA11y", { name })}
                >
                  <PersonAvatar name={name} url={person.avatar_url} size={40} />
                  <span className="min-w-0 flex-1">
                    <span className="flex min-w-0 items-center gap-2">
                      <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                        {name}
                      </span>
                      {person.buddy ? <BuddyBadge /> : null}
                    </span>
                    {person.handle && person.nickname ? (
                      <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
                        @{person.handle}
                      </span>
                    ) : null}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

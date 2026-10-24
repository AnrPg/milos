"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { peopleSearchKey, searchPeople } from "@/api/conversations";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";

import { BuddyBadge } from "./ConversationRow";
import { personLabel } from "./conversation-model";
import { useConversationsToken, useOpenConversation } from "./use-conversations";

const MIN_QUERY = 2;
const DEBOUNCE_MS = 300;

/**
 * «Search or start a conversation» (ADR-193 §4): people across Palee by name
 * or @handle; picking one opens (or finds) your conversation with them.
 * While the box is empty, `children` (the conversations) show instead.
 */
export function PeopleSearchPicker({ onOpened, children }: { onOpened?: () => void; children?: ReactNode }) {
  const t = useTranslations("Conversations");
  const tUi = useUiTranslations();
  const token = useConversationsToken();
  const [text, setText] = useState("");
  const [term, setTerm] = useState("");
  const open = useOpenConversation(onOpened);

  useEffect(() => {
    const next = text.trim();
    const timeout = setTimeout(() => setTerm(next), DEBOUNCE_MS);
    return () => clearTimeout(timeout);
  }, [text]);

  const searching = term.length >= MIN_QUERY;
  const results = useQuery({
    queryKey: peopleSearchKey(term),
    enabled: Boolean(token) && searching,
    queryFn: ({ signal }) => searchPeople(token!, term, signal),
    staleTime: 30_000,
  });
  const people = results.data ?? [];

  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div className="relative">
        <svg
          aria-hidden="true"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="pointer-events-none absolute start-3 top-1/2 -translate-y-1/2"
          style={{ color: "var(--dim)" }}
        >
          <circle cx="11" cy="11" r="7" />
          <path d="m20 20-3.5-3.5" />
        </svg>
        <input
          type="search"
          value={text}
          onChange={(event) => setText(event.target.value)}
          placeholder={t("searchPlaceholder")}
          aria-label={t("searchPlaceholder")}
          className="min-h-11 w-full rounded-2xl ps-9 pe-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)]"
          style={{ background: "var(--card)", color: "var(--text)", border: "1px solid var(--border-strong)" }}
          data-testid="people-search-input"
        />
      </div>

      {open.error ? (
        <p className="px-1 text-sm" role="alert" style={{ color: "var(--danger)" }}>
          {localizeError(open.error, tUi)}
        </p>
      ) : null}

      {searching ? (
        <div className="flex flex-col gap-2" data-testid="people-search-results">
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
      ) : (
        children
      )}
    </div>
  );
}

"use client";

import { useEffect, useState } from "react";

import { listAthletes, type AthleteOption } from "@/api/assigned-workouts";
import { useUiTranslations } from "@/i18n/ui";
import { GROUP_PROGRAMMING_LIMIT } from "@/lib/group-variations";

export type PickedPerson = { id: string; nickname: string };

/**
 * ADR-201: «Also for…» in the profile programming dialog. Adds more people
 * who get the same programming; each is programmed as if they were the only
 * one. Collapsed until staff ask for it, so the one-person flow stays as is.
 */
export function AdditionalPeoplePicker({
  token,
  excludeUserId,
  picked,
  onChange,
  needsBooking,
  collapsible = true,
}: {
  token: string;
  /** The person whose profile this is (always programmed). */
  excludeUserId: string;
  picked: PickedPerson[];
  onChange: (people: PickedPerson[]) => void;
  /** A class mode: each person must have booked the chosen class. */
  needsBooking: boolean;
  /** False when a parent disclosure already hides it until asked for. */
  collapsible?: boolean;
}) {
  const i18n = useUiTranslations();
  const [expanded, setOpen] = useState(picked.length > 0);
  const open = expanded || !collapsible;
  const [query, setQuery] = useState("");
  const [options, setOptions] = useState<AthleteOption[]>([]);

  useEffect(() => {
    if (!open) return;
    let active = true;
    const timer = window.setTimeout(() => {
      listAthletes(token, query, { includeMembers: true })
        .then((people) => {
          if (active) setOptions(Array.isArray(people) ? people : []);
        })
        .catch(() => {
          if (active) setOptions([]);
        });
    }, 250);
    return () => {
      active = false;
      window.clearTimeout(timer);
    };
  }, [open, query, token]);

  const pickedIds = new Set(picked.map((person) => person.id));
  const matches = options.filter((person) => person.id !== excludeUserId && !pickedIds.has(person.id)).slice(0, 8);
  // The profile's own person counts towards the limit.
  const full = picked.length + 1 >= GROUP_PROGRAMMING_LIMIT;

  if (!open) {
    return (
      <button
        type="button"
        className="mt-3 rounded-full px-3 py-1.5 text-xs font-semibold"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
        onClick={() => setOpen(true)}
      >
        {i18n("groupProgrammingAlsoFor")}
      </button>
    );
  }

  return (
    <div className="mt-3 rounded-xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-xs font-semibold" style={{ color: "var(--text)" }}>{i18n("groupProgrammingAlsoFor")}</p>
      <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
        {i18n("groupProgrammingAlsoForHint")}
        {needsBooking ? ` ${i18n("groupProgrammingClassNeedsBooking")}` : ""}
      </p>
      {picked.length ? (
        <ul className="mt-2 flex flex-wrap gap-1.5">
          {picked.map((person) => (
            <li key={person.id}>
              <button
                type="button"
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }}
                aria-label={i18n("groupProgrammingRemovePerson", { nickname: person.nickname })}
                onClick={() => onChange(picked.filter((other) => other.id !== person.id))}
              >
                {person.nickname} ✕
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      <label className="mt-2 block text-xs font-semibold" style={{ color: "var(--text)" }}>
        {i18n("groupProgrammingSearchPeople")}
        <input
          type="search"
          className="mt-1 w-full rounded-xl px-3 py-2 text-sm"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
      </label>
      {full ? (
        <p className="mt-2 text-xs" style={{ color: "var(--muted)" }}>
          {i18n("groupVariationLimit", { limit: GROUP_PROGRAMMING_LIMIT })}
        </p>
      ) : matches.length ? (
        <ul className="mt-2 space-y-1">
          {matches.map((person) => (
            <li key={person.id}>
              <button
                type="button"
                className="w-full rounded-lg px-3 py-1.5 text-start text-sm"
                style={{ background: "var(--panel-muted)", color: "var(--text)" }}
                onClick={() => onChange([...picked, { id: person.id, nickname: person.nickname }])}
              >
                {person.nickname}
              </button>
            </li>
          ))}
        </ul>
      ) : query.trim() ? (
        <p className="mt-2 text-xs" style={{ color: "var(--muted)" }}>{i18n("groupProgrammingNoMatches")}</p>
      ) : null}
    </div>
  );
}

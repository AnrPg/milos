"use client";

import { useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { INTEREST_LEVELS, fetchMyInterests, saveMyInterests, type AccountInterests, type InterestLevel } from "@/api/interests";
import { getBoxVocabulary } from "@/api/public-profile";
import { ChoiceChips } from "@/components/filters/FilterPage";
import { useSession } from "@/components/session-provider";

export const MY_INTERESTS_KEY = ["my-interests"] as const;
const MAX_DISCIPLINES = 12;

/** «Τι κάνεις» (ADR-183), read once per person and shared by every reader. */
export function useMyInterests() {
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: [...MY_INTERESTS_KEY, currentUser?.id ?? null],
    enabled: Boolean(token && currentUser),
    queryFn: () => fetchMyInterests(token!),
    staleTime: 5 * 60_000,
  });
}

/**
 * Disciplines (grouped like the box vocabulary) and a level. The caller
 * renders the actions; `save` stores the picks, or just continues when
 * nothing was picked and nothing was stored before.
 */
export function InterestsEditor({
  onSaved,
  renderActions,
}: {
  onSaved?: (interests: AccountInterests) => void;
  renderActions: (actions: { save: () => void; busy: boolean; dirty: boolean }) => ReactNode;
}) {
  const t = useTranslations("FirstRun");
  const tags = useTranslations("BoxTags");
  const partners = useTranslations("Partners");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const vocabulary = useQuery({ queryKey: ["box-vocabulary"], queryFn: getBoxVocabulary, staleTime: Infinity });
  const saved = useMyInterests();
  const [disciplines, setDisciplines] = useState<string[] | null>(null);
  const [level, setLevel] = useState<InterestLevel | null | undefined>(undefined);
  const picked = disciplines ?? saved.data?.disciplines ?? [];
  const pickedLevel = level === undefined ? (saved.data?.level ?? null) : level;
  const dirty = disciplines !== null || level !== undefined;
  const save = useMutation({
    mutationFn: () => saveMyInterests(token!, { disciplines: picked, level: pickedLevel }),
    onSuccess: (interests) => {
      queryClient.setQueryData([...MY_INTERESTS_KEY, currentUser?.id ?? null], interests);
      setDisciplines(null);
      setLevel(undefined);
      onSaved?.(interests);
    },
  });

  function submit() {
    if (!token) return;
    if (!dirty && picked.length === 0 && pickedLevel === null) {
      onSaved?.({ disciplines: [], level: null });
      return;
    }
    save.mutate();
  }

  return (
    <div className="flex flex-col gap-6">
      {(vocabulary.data?.discipline_groups ?? []).map((group) => (
        <div key={group.key} className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {tags(["group", group.key].join("."))}
          </h2>
          <ChoiceChips
            ariaLabel={tags(["group", group.key].join("."))}
            multiple
            options={group.items.map((key) => ({ value: key, label: tags(["discipline", key].join(".")) }))}
            selected={picked.filter((key) => group.items.includes(key))}
            onChange={(values) =>
              setDisciplines([...picked.filter((key) => !group.items.includes(key)), ...values].slice(0, MAX_DISCIPLINES))
            }
          />
        </div>
      ))}
      {vocabulary.isError ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t("loadFailed")}</p>
      ) : null}
      <div className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("levelTitle")}</h2>
        <ChoiceChips
          ariaLabel={t("levelTitle")}
          multiple={false}
          options={INTEREST_LEVELS.map((value) => ({ value, label: partners(`level_${value}`) }))}
          selected={pickedLevel ? [pickedLevel] : []}
          onChange={(values) => setLevel((values[0] as InterestLevel | undefined) ?? null)}
        />
      </div>
      {save.isError ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t("saveFailed")}</p>
      ) : null}
      {renderActions({ save: submit, busy: save.isPending, dirty })}
    </div>
  );
}

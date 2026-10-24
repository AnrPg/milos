"use client";

import { useState, type ReactNode } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { PARTNERS_KEY, putPartnerProfile, type PartnersClubOverview } from "@/api/partners";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { useMyInterests } from "@/components/interests/InterestsEditor";
import { useUiTranslations } from "@/i18n/ui";

import { PartnerChip } from "./PartnerBits";
import { partnerErrorMessage } from "./errors";
import { draftRequest, draftValid, profileDraft, toggleIn, type ProfileDraft } from "./partners-model";
import { usePartnersToken } from "./use-partners";

/**
 * The opt-in profile for one club (ADR-169 §2): level, when you train, up to
 * three goals, the disciplines you'd train together (ADR-197; your interests
 * first) and a short line. Gender and a preference are optional and only
 * used to honour preferences; nobody sees them. Saving switches it on;
 * «Παύση» keeps it but takes you out of every deck.
 */
export function PartnerProfileSheet({
  clubId,
  overview,
  onClose,
}: {
  clubId: string;
  overview: PartnersClubOverview;
  onClose: () => void;
}) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const { options, profile } = overview;
  const [draft, setDraft] = useState<ProfileDraft>(() => profileDraft(profile));
  const [more, setMore] = useState(Boolean(profile?.gender));
  const tags = useTranslations("BoxTags");
  const interests = useMyInterests().data?.disciplines ?? [];
  const [allDisciplines, setAllDisciplines] = useState(false);
  const offered = new Set(options.disciplines);
  const shortList = Array.from(new Set([...draft.disciplines, ...interests])).filter((key) => offered.has(key));
  const disciplineKeys = allDisciplines || shortList.length === 0 ? options.disciplines : shortList;
  const set = (patch: Partial<ProfileDraft>) => setDraft((current) => ({ ...current, ...patch }));

  const save = useMutation({
    mutationFn: (active: boolean) => putPartnerProfile(token!, clubId, draftRequest(draft, active)),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: PARTNERS_KEY });
      onClose();
    },
  });
  const valid = draftValid(draft, options);

  return (
    <Sheet
      labelId={`partner-profile-${clubId}`}
      eyebrow={t("title")}
      title={profile ? t("profileEditTitle") : t("profileTitle")}
      onClose={onClose}
      footer={
        <>
          {profile?.active ? (
            <SheetButton disabled={save.isPending} onClick={() => save.mutate(false)}>{t("pause")}</SheetButton>
          ) : (
            <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          )}
          <SheetButton primary disabled={!valid || save.isPending} onClick={() => save.mutate(true)}>
            {save.isPending ? t("saving") : profile?.active ? t("save") : t("turnOn")}
          </SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("profileHint")}</p>

        <Field label={t("levelLabel")}>
          <div role="radiogroup" aria-label={t("levelLabel")} className="flex flex-wrap gap-2">
            {options.levels.map((level) => (
              <ChoicePill key={level} selected={draft.level === level} onSelect={() => set({ level })}>
                {t(`level_${level}`)}
              </ChoicePill>
            ))}
          </div>
        </Field>

        <Field label={t("timesLabel")}>
          <div role="group" aria-label={t("timesLabel")} className="flex flex-wrap gap-2">
            {options.times.map((time) => (
              <PartnerChip key={time} pressed={draft.times.includes(time)} onToggle={() => set({ times: toggleIn(draft.times, time, options.times) })}>
                {t(`time_${time}`)}
              </PartnerChip>
            ))}
          </div>
        </Field>

        <Field label={t("goalsLabel", { max: options.max_goals })}>
          <div role="group" aria-label={t("goalsLabel", { max: options.max_goals })} className="flex flex-wrap gap-2">
            {options.goals.map((goal) => {
              const pressed = draft.goals.includes(goal);
              return (
                <PartnerChip
                  key={goal}
                  pressed={pressed}
                  disabled={!pressed && draft.goals.length >= options.max_goals}
                  onToggle={() => set({ goals: toggleIn(draft.goals, goal, options.goals, options.max_goals) })}
                >
                  {t(`goal_${goal}`)}
                </PartnerChip>
              );
            })}
          </div>
        </Field>

        <Field label={t("disciplinesLabel", { max: options.max_disciplines })}>
          <div role="group" aria-label={t("disciplinesLabel", { max: options.max_disciplines })} className="flex flex-wrap gap-2">
            {disciplineKeys.map((key) => {
              const pressed = draft.disciplines.includes(key);
              return (
                <PartnerChip
                  key={key}
                  pressed={pressed}
                  disabled={!pressed && draft.disciplines.length >= options.max_disciplines}
                  onToggle={() => set({ disciplines: toggleIn(draft.disciplines, key, options.disciplines, options.max_disciplines) })}
                >
                  {tags(`discipline.${key}`)}
                </PartnerChip>
              );
            })}
          </div>
          {shortList.length > 0 && shortList.length < options.disciplines.length ? (
            <button
              type="button"
              aria-expanded={allDisciplines}
              onClick={() => setAllDisciplines((value) => !value)}
              className="min-h-11 self-start text-sm font-semibold"
              style={{ color: "var(--primary)" }}
            >
              {allDisciplines ? t("fewerDisciplines") : t("allDisciplines")}
            </button>
          ) : null}
        </Field>

        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("aboutLabel")}
          <input
            value={draft.about}
            maxLength={options.about_max}
            onChange={(event) => set({ about: event.target.value })}
            placeholder={t("aboutPlaceholder")}
            className="min-h-11 rounded-2xl px-3 text-sm font-normal"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
          <span className="text-xs font-normal" style={{ color: "var(--dim)" }}>
            {t("aboutCount", { count: draft.about.length, max: options.about_max })}
          </span>
        </label>

        {more ? (
          <div className="flex flex-col gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("safetyPrefsHint")}</p>
            <Field label={t("genderLabel")}>
              <div role="radiogroup" aria-label={t("genderLabel")} className="flex flex-wrap gap-2">
                <ChoicePill selected={!draft.gender} onSelect={() => set({ gender: null })}>{t("gender_unset")}</ChoicePill>
                {options.genders.map((gender) => (
                  <ChoicePill key={gender} selected={draft.gender === gender} onSelect={() => set({ gender })}>
                    {t(`gender_${gender}`)}
                  </ChoicePill>
                ))}
              </div>
            </Field>
            <Field label={t("preferenceLabel")}>
              <div role="radiogroup" aria-label={t("preferenceLabel")} className="flex flex-wrap gap-2">
                {options.gender_preferences.map((preference) => (
                  <ChoicePill
                    key={preference}
                    selected={draft.gender_preference === preference}
                    onSelect={() => set({ gender_preference: preference })}
                  >
                    {t(`preference_${preference}`)}
                  </ChoicePill>
                ))}
              </div>
            </Field>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => setMore(true)}
            className="min-h-11 self-start text-sm font-semibold"
            style={{ color: "var(--primary)" }}
          >
            {t("safetyPrefsOpen")}
          </button>
        )}

        <ErrorLine message={partnerErrorMessage(save.error, t, tUi)} />
      </div>
    </Sheet>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{label}</p>
      {children}
    </div>
  );
}

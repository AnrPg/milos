"use client";

import { useState, type ReactNode } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { PARTNERS_KEY, putPartnerProfile, type PartnersOverview } from "@/api/partners";
import { SwitchRow } from "@/components/buddy/BuddyBits";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { useMyInterests } from "@/components/interests/InterestsEditor";
import { useUiTranslations } from "@/i18n/ui";

import { PartnerChip } from "./PartnerBits";
import { partnerErrorMessage } from "./errors";
import { draftErrors, draftRequest, profileDraft, toggleIn, type DraftErrors, type ProfileDraft } from "./partners-model";
import { usePartnersToken } from "./use-partners";

/**
 * My Partners profile (ADR-280): the 18+ confirmation on the first save,
 * «Δείξε το box μου» (on unless I switch it off), level, when I train, up to
 * three goals, the disciplines I'd train together (my interests first) and
 * a short line. Gender and a preference are optional, folded away and only
 * used to honour preferences; nobody sees them. «Παύση» keeps the profile
 * but takes me out of the deck.
 */
export function PartnerProfileSheet({ overview, onClose }: { overview: PartnersOverview; onClose: () => void }) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const tags = useTranslations("BoxTags");
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const { options, profile } = overview;
  const firstSave = !profile;
  const [draft, setDraft] = useState<ProfileDraft>(() => profileDraft(profile));
  const [tried, setTried] = useState(false);
  const [more, setMore] = useState(Boolean(profile?.gender) || (profile?.gender_preference ?? "any") !== "any");
  const interests = useMyInterests().data?.disciplines ?? [];
  const [allDisciplines, setAllDisciplines] = useState(false);
  const offered = new Set(options.disciplines);
  const shortList = Array.from(new Set([...draft.disciplines, ...interests])).filter((key) => offered.has(key));
  const disciplineKeys = allDisciplines || shortList.length === 0 ? options.disciplines : shortList;
  const set = (patch: Partial<ProfileDraft>) => setDraft((current) => ({ ...current, ...patch }));
  const errors: DraftErrors = tried ? draftErrors(draft, options, firstSave) : {};

  const save = useMutation({
    mutationFn: (active: boolean) => putPartnerProfile(token!, draftRequest(draft, { active, firstSave })),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: PARTNERS_KEY });
      onClose();
    },
  });
  const submit = (active: boolean) => {
    setTried(true);
    if (Object.keys(draftErrors(draft, options, firstSave)).length > 0) return;
    save.mutate(active);
  };
  const live = profile?.active && !profile.paused;

  return (
    <Sheet
      labelId="partner-profile"
      eyebrow={t("title")}
      title={profile ? t("profileEditTitle") : t("profileTitle")}
      onClose={onClose}
      footer={
        <>
          {live ? (
            <SheetButton disabled={save.isPending} onClick={() => save.mutate(false)}>{t("pause")}</SheetButton>
          ) : (
            <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          )}
          <SheetButton primary disabled={save.isPending} onClick={() => submit(true)}>
            {save.isPending ? t("saving") : live ? t("save") : t("turnOn")}
          </SheetButton>
        </>
      }
    >
      <form
        className="flex flex-col gap-5"
        noValidate
        onSubmit={(event) => {
          event.preventDefault();
          submit(true);
        }}
        data-testid="partner-profile-form"
      >
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("profileHint")}</p>

        {firstSave ? (
          <div className="flex flex-col gap-1">
            <label className="flex min-h-11 items-center gap-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
              <input
                type="checkbox"
                checked={draft.adult}
                onChange={(event) => set({ adult: event.target.checked })}
                aria-invalid={errors.adult ? true : undefined}
                aria-describedby={errors.adult ? "partner-adult-error" : undefined}
                className="h-5 w-5 shrink-0"
                style={{ accentColor: "var(--primary)" }}
              />
              {t("adultLabel")}
            </label>
            <FieldError id="partner-adult-error" show={errors.adult}>{t("adultRequired")}</FieldError>
          </div>
        ) : null}

        <div className="rounded-2xl px-3 py-1" style={{ background: "var(--panel-muted)" }}>
          <SwitchRow checked={draft.show_box} onChange={(show_box) => set({ show_box })} label={t("showBoxLabel")} hint={t("showBoxHint")} />
        </div>

        <Field label={t("levelLabel")} error={errors.level ? t("levelRequired") : null} errorId="partner-level-error">
          <div role="radiogroup" aria-label={t("levelLabel")} className="flex flex-wrap gap-2">
            {options.levels.map((level) => (
              <ChoicePill key={level} selected={draft.level === level} onSelect={() => set({ level })}>
                {t(`level_${level}`)}
              </ChoicePill>
            ))}
          </div>
        </Field>

        <Field label={t("timesLabel")} error={errors.times ? t("timesRequired") : null} errorId="partner-times-error">
          <div role="group" aria-label={t("timesLabel")} className="flex flex-wrap gap-2">
            {options.times.map((time) => (
              <PartnerChip key={time} pressed={draft.times.includes(time)} onToggle={() => set({ times: toggleIn(draft.times, time, options.times) })}>
                {t(`time_${time}`)}
              </PartnerChip>
            ))}
          </div>
        </Field>

        <Field label={t("goalsLabel", { max: options.max_goals })} error={errors.goals ? t("goalsRequired", { max: options.max_goals }) : null} errorId="partner-goals-error">
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

        {options.disciplines.length > 0 ? (
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
        ) : null}

        <div className="flex flex-col gap-1">
          <label htmlFor="partner-about" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("aboutLabel")}
          </label>
          <textarea
            id="partner-about"
            value={draft.about}
            maxLength={options.about_max}
            rows={2}
            onChange={(event) => set({ about: event.target.value })}
            placeholder={t("aboutPlaceholder")}
            aria-invalid={errors.about ? true : undefined}
            className="resize-none rounded-2xl px-3 py-2 text-sm"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {t("aboutCount", { count: draft.about.length, max: options.about_max })}
          </span>
          <FieldError id="partner-about-error" show={errors.about}>{t("aboutTooLong", { max: options.about_max })}</FieldError>
        </div>

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
                  <ChoicePill key={preference} selected={draft.gender_preference === preference} onSelect={() => set({ gender_preference: preference })}>
                    {t(`preference_${preference}`)}
                  </ChoicePill>
                ))}
              </div>
            </Field>
          </div>
        ) : (
          <button type="button" aria-expanded={false} onClick={() => setMore(true)} className="min-h-11 self-start text-sm font-semibold" style={{ color: "var(--primary)" }}>
            {t("safetyPrefsOpen")}
          </button>
        )}

        <ErrorLine message={partnerErrorMessage(save.error, t, tUi)} />
      </form>
    </Sheet>
  );
}

function Field({ label, error, errorId, children }: { label: string; error?: string | null; errorId?: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{label}</p>
      {children}
      <FieldError id={errorId} show={Boolean(error)}>{error ?? ""}</FieldError>
    </div>
  );
}

function FieldError({ id, show, children }: { id?: string; show?: boolean; children: string }) {
  if (!show) return null;
  return (
    <p id={id} role="alert" className="text-xs font-semibold" style={{ color: "var(--danger)" }}>
      {children}
    </p>
  );
}

"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useMemo, useRef, useState, type Dispatch, type SetStateAction } from "react";

import { ApiError } from "@/api/client";
import {
  getBoxVocabulary,
  getPublicProfile,
  publishProfile,
  saveProfileDraft,
  suggestTag,
  unpublishProfile,
  type BoxPublicProfile,
  type BoxVocabulary,
  type MediaItem,
  type TagList,
} from "@/api/public-profile";
import { COMMON_LANGUAGES, ISO_639_1, languageNames } from "@/components/admin/public-page/languages";
import { TagPicker, type TagGroup } from "@/components/admin/public-page/TagPicker";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { BoxPhotoUploadError, uploadBoxPhoto } from "@/lib/box-photo-upload";

type Draft = {
  about: string;
  disciplines: string[];
  services: string[];
  audiences: string[];
  languages: string[];
  amenities: string[];
  cover: MediaItem | null;
  photos: MediaItem[];
  coachIds: string[];
};

type Step = "about" | "photos" | "offer" | "people" | "coaches" | "amenities";
const STEPS: Step[] = ["about", "photos", "offer", "people", "coaches", "amenities"];
const MAX_PHOTOS = 12;
const MAX_LANGUAGES = 10;
const MAX_ABOUT = 2000;

type Picker = { list: TagList | "languages" } | null;

function toDraft(profile: BoxPublicProfile): Draft {
  return {
    about: profile.about ?? "",
    disciplines: profile.disciplines,
    services: profile.services,
    audiences: profile.audiences,
    languages: profile.languages,
    amenities: profile.amenities,
    cover: profile.cover,
    photos: profile.photos,
    coachIds: profile.coaches.map((coach) => coach.id),
  };
}

const sameDraft = (a: Draft, b: Draft) =>
  JSON.stringify({ ...a, cover: a.cover?.id ?? null, photos: a.photos.map((photo) => photo.id) }) ===
  JSON.stringify({ ...b, cover: b.cover?.id ?? null, photos: b.photos.map((photo) => photo.id) });

/** «Δημόσια σελίδα»: the gym's public «Σχετικά», edited step by step (plan §5a, boards 3 and 3b). */
export function PublicPageEditor() {
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const i18n = useUiTranslations();
  const profile = useQuery({
    queryKey: ["admin", "public-profile"],
    queryFn: () => getPublicProfile(token!),
    enabled: Boolean(token),
  });
  const vocabulary = useQuery({ queryKey: ["box-vocabulary"], queryFn: getBoxVocabulary, staleTime: Infinity });

  if (!token || !profile.data || !vocabulary.data) {
    return (
      <p className="p-6 text-sm" style={{ color: profile.isError || vocabulary.isError ? "var(--danger)" : "var(--dim)" }}>
        {profile.isError || vocabulary.isError ? localizeError(profile.error ?? vocabulary.error, i18n) : i18n("loading33ce417")}
      </p>
    );
  }
  return <Editor token={token} profile={profile.data} vocabulary={vocabulary.data} />;
}

function Editor({ token, profile, vocabulary }: { token: string; profile: BoxPublicProfile; vocabulary: BoxVocabulary }) {
  const t = useTranslations("AdminPublicPage");
  const tags = useTranslations("BoxTags");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const [server, setServer] = useState(profile);
  const saved = useMemo(() => toDraft(server), [server]);
  const [draft, setDraft] = useState<Draft>(saved);
  // A gym that never saved anything walks the steps; afterwards they are tabs.
  const [step, setStep] = useState<Step>("about");
  const [picker, setPicker] = useState<Picker>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const firstRun = profile.lock_version === 0;
  const dirty = !sameDraft(draft, saved);

  const names = useMemo(() => languageNames(locale), [locale]);

  const accept = (next: BoxPublicProfile, message: string | null) => {
    setServer(next);
    setDraft(toDraft(next));
    setError(null);
    setNotice(message);
    queryClient.setQueryData(["admin", "public-profile"], next);
  };

  const fail = (cause: unknown) => {
    setNotice(null);
    setError(
      cause instanceof ApiError && cause.status === 409
        ? t("staleProfile")
        : cause instanceof BoxPhotoUploadError
          ? t("photoFailed")
          : localizeError(cause, i18n),
    );
  };

  const saveDraft = async () =>
    saveProfileDraft(token, {
      about: draft.about.trim() || null,
      disciplines: draft.disciplines,
      services: draft.services,
      audiences: draft.audiences,
      languages: draft.languages,
      amenities: draft.amenities,
      cover_photo_id: draft.cover?.id ?? null,
      photo_ids: draft.photos.map((photo) => photo.id),
      coach_ids: draft.coachIds,
      lock_version: server.lock_version,
    });

  const save = useMutation({ mutationFn: saveDraft, onSuccess: (next) => accept(next, t("draftSaved")), onError: fail });
  const publish = useMutation({
    mutationFn: async () => {
      const current = dirty ? await saveDraft() : server;
      return publishProfile(token, current.lock_version);
    },
    onSuccess: (next) => accept(next, t("publishedNotice")),
    onError: fail,
  });
  const unpublish = useMutation({
    mutationFn: () => unpublishProfile(token),
    onSuccess: (next) => accept(next, t("unpublishedNotice")),
    onError: fail,
  });

  const missing = {
    about: draft.about.trim() === "",
    disciplines: draft.disciplines.length === 0,
  };
  const ready = !missing.about && !missing.disciplines;
  const changes = dirty || server.unpublished_changes;
  const status = !server.published ? "draft" : changes ? "changes" : "live";
  const busy = save.isPending || publish.isPending || unpublish.isPending;

  const groupsFor = (list: TagList | "languages"): TagGroup[] => {
    if (list === "disciplines")
      return vocabulary.discipline_groups.map((group) => ({
        key: group.key,
        label: tags(`group.${group.key}`),
        items: group.items.map((value) => ({ value, label: tags(`discipline.${value}`) })),
      }));
    if (list === "languages") {
      const option = (code: string) => {
        const name = names(code);
        return { value: code, label: name.own, search: `${name.viewer} ${name.english} ${code}` };
      };
      return [
        { key: "common", label: t("commonLanguages"), items: COMMON_LANGUAGES.map(option), open: true },
        {
          key: "all",
          label: t("otherLanguages"),
          items: ISO_639_1.filter((code) => !COMMON_LANGUAGES.includes(code))
            .map(option)
            .sort((a, b) => a.label.localeCompare(b.label, locale)),
        },
      ];
    }
    const prefix = { audiences: "audience", amenities: "amenity", services: "service" }[list];
    return [
      {
        key: list,
        label: null,
        items: vocabulary[list]
          .filter((value) => list !== "audiences" || value !== "returning_from_injury" || draft.disciplines.includes("physio_rehab"))
          .map((value) => ({
            value,
            label: tags(`${prefix}.${value}`),
            hint: list === "amenities" && tags.has(`amenityHint.${value}`) ? tags(`amenityHint.${value}`) : undefined,
          })),
      },
    ];
  };

  const label = (list: TagList | "languages", value: string) =>
    list === "languages"
      ? names(value).own
      : tags(`${{ disciplines: "discipline", audiences: "audience", amenities: "amenity", services: "service" }[list]}.${value}`);

  const card = (list: TagList | "languages", title: string, emptyText: string) => (
    <section
      className="flex flex-col gap-3 rounded-3xl p-4"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      aria-label={title}
    >
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>
          {title}
        </h3>
        <button
          type="button"
          onClick={() => setPicker({ list })}
          className="text-sm font-semibold"
          style={{ color: "var(--primary)" }}
          aria-label={t("editList", { list: title })}
        >
          {draft[list].length > 0 ? t("edit") : t("add")}
        </button>
      </div>
      {draft[list].length > 0 ? (
        <ul className="flex flex-wrap gap-2">
          {draft[list].map((value) => (
            <li
              key={value}
              className="inline-flex items-center gap-1 rounded-full py-1 pl-3 pr-1 text-sm font-semibold"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
            >
              {label(list, value)}
              <button
                type="button"
                aria-label={t("remove", { name: label(list, value) })}
                onClick={() => setDraft({ ...draft, [list]: draft[list].filter((other) => other !== value) })}
                className="grid h-6 w-6 place-items-center rounded-full"
                style={{ color: "var(--dim)" }}
              >
                <span aria-hidden="true">✕</span>
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm" style={{ color: "var(--dim)" }}>
          {emptyText}
        </p>
      )}
    </section>
  );

  const index = STEPS.indexOf(step);

  return (
    <main className="min-h-screen px-6 py-10 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-3xl flex-col gap-6 pb-36">
        <header className="flex flex-col gap-4">
          <div className="flex flex-wrap items-center gap-3">
            <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>
              {t("title")}
            </h1>
            <span
              className="rounded-full px-3 py-1 text-xs font-bold"
              style={{
                background: "var(--panel-muted)",
                border: "1px solid var(--border)",
                color: status === "live" ? "var(--success)" : status === "changes" ? "var(--warning)" : "var(--muted)",
              }}
            >
              {t(`status_${status}`)}
            </span>
          </div>
          <div
            className="flex flex-col gap-3 rounded-3xl p-4 sm:flex-row sm:items-center sm:justify-between"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <ul className="flex flex-col gap-1 text-sm" aria-label={t("checklist")}>
              <li style={{ color: missing.about ? "var(--warning)" : "var(--success)" }}>
                {missing.about ? "○" : "✓"} {t("checkAbout")}
              </li>
              <li style={{ color: missing.disciplines ? "var(--warning)" : "var(--success)" }}>
                {missing.disciplines ? "○" : "✓"} {t("checkDisciplines")}
              </li>
              <li style={{ color: draft.cover || draft.photos.length ? "var(--success)" : "var(--dim)" }}>
                {draft.cover || draft.photos.length ? "✓" : "○"} {t("checkPhotos")}
              </li>
            </ul>
            <div className="flex flex-wrap gap-2">
              {server.published ? (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => unpublish.mutate()}
                  className="min-h-11 rounded-full px-5 text-sm font-semibold disabled:opacity-40"
                  style={{ background: "var(--border)", color: "var(--text-soft)" }}
                >
                  {t("unpublish")}
                </button>
              ) : null}
              <button
                type="button"
                disabled={busy || !ready || (server.published && !changes)}
                onClick={() => publish.mutate()}
                className="min-h-11 rounded-full px-6 text-sm font-bold disabled:opacity-40"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {t("publish")}
              </button>
            </div>
          </div>
        </header>

        <nav aria-label={t("steps")} className="flex gap-1 overflow-x-auto" style={{ borderBottom: "1px solid var(--border)" }}>
          {STEPS.map((key, at) => (
            <button
              key={key}
              type="button"
              ref={step === key ? (node) => node?.scrollIntoView({ block: "nearest", inline: "nearest" }) : undefined}
              aria-current={step === key ? "step" : undefined}
              onClick={() => setStep(key)}
              className="shrink-0 px-3 py-2.5 text-sm font-bold"
              style={{
                color: step === key ? "var(--text)" : "var(--dim)",
                borderBottom: `2px solid ${step === key ? "var(--primary)" : "transparent"}`,
              }}
            >
              {firstRun ? `${at + 1}. ` : ""}
              {t(`step_${key}`)}
            </button>
          ))}
        </nav>

        {step === "about" ? (
          <label className="flex flex-col gap-2">
            <span className="text-sm" style={{ color: "var(--muted)" }}>
              {t("aboutHint")}
            </span>
            <textarea
              value={draft.about}
              maxLength={MAX_ABOUT}
              rows={9}
              aria-label={t("step_about")}
              onChange={(event) => setDraft({ ...draft, about: event.target.value })}
              className="rounded-3xl px-4 py-3 text-sm leading-6 outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
            <span className="self-end font-mono text-xs" style={{ color: "var(--dim)" }}>
              {draft.about.length}/{MAX_ABOUT}
            </span>
          </label>
        ) : null}

        {step === "photos" ? (
          <PhotosStep token={token} draft={draft} setDraft={setDraft} onError={fail} />
        ) : null}

        {step === "offer" ? (
          <div className="flex flex-col gap-4">
            {card("disciplines", t("disciplines"), t("disciplinesEmpty"))}
            {card("services", t("services"), t("servicesEmpty"))}
          </div>
        ) : null}

        {step === "people" ? (
          <div className="flex flex-col gap-4">
            {card("audiences", t("audiences"), t("audiencesEmpty"))}
            {card("languages", t("languages"), t("languagesEmpty"))}
          </div>
        ) : null}

        {step === "coaches" ? (
          <CoachesStep
            candidates={server.coach_candidates}
            picked={draft.coachIds}
            onChange={(coachIds) => setDraft({ ...draft, coachIds })}
          />
        ) : null}

        {step === "amenities" ? card("amenities", t("amenities"), t("amenitiesEmpty")) : null}

        <div className="flex justify-between gap-3">
          <button
            type="button"
            disabled={index === 0}
            onClick={() => setStep(STEPS[index - 1])}
            className="min-h-11 rounded-full px-5 text-sm font-semibold disabled:invisible"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
          >
            {t("back")}
          </button>
          {index < STEPS.length - 1 ? (
            <button
              type="button"
              onClick={() => {
                if (dirty) save.mutate();
                setStep(STEPS[index + 1]);
              }}
              className="min-h-11 rounded-full px-6 text-sm font-bold"
              style={{ background: "var(--text)", color: "var(--bg)" }}
            >
              {t("next")}
            </button>
          ) : null}
        </div>
      </div>

      <div
        className="fixed inset-x-0 bottom-0 z-[55] px-6 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-3"
        style={{ background: "color-mix(in srgb, var(--bg) 92%, transparent)", borderTop: "1px solid var(--border)" }}
      >
        <div className="mx-auto flex max-w-3xl flex-wrap items-center justify-end gap-x-3 gap-y-2">
          <p role="status" className="mr-auto w-full text-sm sm:w-auto" style={{ color: error ? "var(--danger)" : "var(--muted)" }}>
            {error ?? (dirty ? t("unsavedDraft") : notice)}
          </p>
          <button
            type="button"
            disabled={!dirty || busy}
            onClick={() => setDraft(saved)}
            className="rounded-full px-5 py-2.5 text-sm font-semibold disabled:opacity-40"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
          >
            {t("discard")}
          </button>
          <button
            type="button"
            disabled={!dirty || busy}
            onClick={() => save.mutate()}
            className="rounded-full px-6 py-2.5 text-sm font-bold disabled:opacity-40"
            style={{ background: "var(--text)", color: "var(--bg)" }}
          >
            {t("saveDraft")}
          </button>
        </div>
      </div>

      {picker ? (
        <TagPicker
          title={t(picker.list)}
          groups={groupsFor(picker.list)}
          selected={draft[picker.list]}
          max={picker.list === "languages" ? MAX_LANGUAGES : undefined}
          onClose={() => setPicker(null)}
          onDone={(values) => {
            setDraft({
              ...draft,
              [picker.list]: values,
              // Welcoming people back from injury needs physiotherapy (board 3b).
              ...(picker.list === "disciplines" && !values.includes("physio_rehab")
                ? { audiences: draft.audiences.filter((value) => value !== "returning_from_injury") }
                : {}),
            });
            setPicker(null);
          }}
          footer={
            picker.list === "languages"
              ? undefined
              : (query) => <SuggestTag token={token} list={picker.list as TagList} initial={query} />
          }
        />
      ) : null}
    </main>
  );
}

/** «Δεν το βρίσκεις; Πρότεινέ το» (board 3b Q5): goes to review, never onto the page. */
/**
 * Board 4 Q4: the owner picks which of the gym's staff the page shows as
 * coaches; they go live with «Δημοσίευση». Shown in the gym's staff order.
 */
function CoachesStep({
  candidates,
  picked,
  onChange,
}: {
  candidates: BoxPublicProfile["coach_candidates"];
  picked: string[];
  onChange: (ids: string[]) => void;
}) {
  const t = useTranslations("AdminPublicPage");
  if (candidates.length === 0) {
    return (
      <p className="rounded-3xl p-5 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--muted)" }}>
        {t("coachesNone")}
      </p>
    );
  }
  const toggle = (id: string) => {
    const next = new Set(picked);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    onChange(candidates.map((coach) => coach.id).filter((candidate) => next.has(candidate)));
  };
  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm" style={{ color: "var(--muted)" }}>{t("coachesHint")}</p>
      <ul className="flex flex-col overflow-hidden rounded-3xl" style={{ border: "1px solid var(--border)" }}>
        {candidates.map((coach, at) => {
          const on = picked.includes(coach.id);
          return (
            <li key={coach.id} style={{ borderTop: at === 0 ? "none" : "1px solid var(--border)" }}>
              <label className="flex min-h-14 cursor-pointer items-center gap-3 px-4 py-2">
                {coach.avatar_url ? (
                  // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
                  <img src={coach.avatar_url} alt="" className="h-10 w-10 shrink-0 rounded-full object-cover" />
                ) : (
                  <span
                    aria-hidden="true"
                    className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-sm font-extrabold"
                    style={{ background: "var(--panel-raised)", color: "var(--text)" }}
                  >
                    {(coach.nickname ?? "?").slice(0, 1).toUpperCase()}
                  </span>
                )}
                <span className="flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{coach.nickname ?? "?"}</span>
                <input type="checkbox" role="switch" checked={on} onChange={() => toggle(coach.id)} className="h-5 w-5" />
              </label>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function SuggestTag({ token, list, initial }: { token: string; list: TagList; initial: string }) {
  const t = useTranslations("AdminPublicPage");
  const [name, setName] = useState(initial);
  const [open, setOpen] = useState(false);
  const send = useMutation({ mutationFn: () => suggestTag(token, list, name.trim()) });

  if (send.isSuccess) {
    return (
      <p role="status" className="text-sm" style={{ color: "var(--success)" }}>
        {t("suggestionSent")}
      </p>
    );
  }
  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="self-start text-sm font-semibold" style={{ color: "var(--primary)" }}>
        {initial ? t("suggestNamed", { name: initial }) : t("suggest")}
      </button>
    );
  }
  return (
    <form
      className="flex flex-col gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        send.mutate();
      }}
    >
      <span className="text-sm" style={{ color: "var(--muted)" }}>
        {t("suggestHint")}
      </span>
      <div className="flex gap-2">
        <input
          value={name}
          maxLength={60}
          aria-label={t("suggest")}
          onChange={(event) => setName(event.target.value)}
          className="min-w-0 flex-1 rounded-2xl px-4 py-2.5 text-sm outline-none"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <button
          type="submit"
          disabled={name.trim().length < 2 || send.isPending}
          className="rounded-full px-5 text-sm font-bold disabled:opacity-40"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("send")}
        </button>
      </div>
      {send.isError ? (
        <p className="text-sm" style={{ color: "var(--danger)" }}>
          {t("suggestionFailed")}
        </p>
      ) : null}
    </form>
  );
}

/** Board 3 Q6: a separate cover slot on top, then the gallery; any photo can become the cover. */
function PhotosStep({
  token,
  draft,
  setDraft,
  onError,
}: {
  token: string;
  draft: Draft;
  setDraft: Dispatch<SetStateAction<Draft>>;
  onError: (cause: unknown) => void;
}) {
  const t = useTranslations("AdminPublicPage");
  const coverInput = useRef<HTMLInputElement>(null);
  const galleryInput = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(0);

  const upload = async (files: File[], target: "cover" | "gallery") => {
    const room = target === "cover" ? 1 : MAX_PHOTOS - draft.photos.length - uploading;
    const chosen = files.slice(0, Math.max(room, 0));
    setUploading((count) => count + chosen.length);
    for (const file of chosen) {
      try {
        const media = await uploadBoxPhoto(token, file);
        setDraft((current) =>
          target === "cover" ? { ...current, cover: media } : { ...current, photos: [...current.photos, media] },
        );
      } catch (cause) {
        onError(cause);
      } finally {
        setUploading((count) => count - 1);
      }
    }
  };

  const move = (from: number, to: number) => {
    const photos = [...draft.photos];
    const [photo] = photos.splice(from, 1);
    photos.splice(to, 0, photo);
    setDraft({ ...draft, photos });
  };

  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-2" aria-label={t("cover")}>
        <h2 className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
          {t("cover")}
        </h2>
        <p className="text-sm" style={{ color: "var(--muted)" }}>
          {t("coverHint")}
        </p>
        {draft.cover?.url ? (
          <div className="relative overflow-hidden rounded-3xl" style={{ border: "1px solid var(--border)" }}>
            {/* eslint-disable-next-line @next/next/no-img-element -- media URLs come from object storage */}
            <img src={draft.cover.url} alt={t("cover")} className="aspect-[2/1] w-full object-cover" />
            <div className="absolute bottom-3 right-3 flex gap-2">
              <button
                type="button"
                onClick={() => coverInput.current?.click()}
                className="rounded-full px-4 py-2 text-xs font-bold"
                style={{ background: "var(--panel-raised)", color: "var(--text)" }}
              >
                {t("replace")}
              </button>
              <button
                type="button"
                onClick={() => setDraft({ ...draft, cover: null })}
                className="rounded-full px-4 py-2 text-xs font-bold"
                style={{ background: "var(--panel-raised)", color: "var(--danger)" }}
              >
                {t("removePhoto")}
              </button>
            </div>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => coverInput.current?.click()}
            className="grid aspect-[2/1] w-full place-items-center rounded-3xl text-sm font-semibold"
            style={{ border: "2px dashed var(--border)", color: "var(--muted)" }}
          >
            {t("addCover")}
          </button>
        )}
        <input
          ref={coverInput}
          type="file"
          accept="image/*"
          hidden
          onChange={(event) => {
            void upload(Array.from(event.target.files ?? []), "cover");
            event.target.value = "";
          }}
        />
      </section>

      <section className="flex flex-col gap-2" aria-label={t("gallery")}>
        <div className="flex items-baseline justify-between">
          <h2 className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
            {t("gallery")}
          </h2>
          <span className="font-mono text-xs" style={{ color: "var(--dim)" }}>
            {draft.photos.length}/{MAX_PHOTOS}
          </span>
        </div>
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {draft.photos.map((photo, at) => (
            <li key={photo.id} className="relative overflow-hidden rounded-2xl" style={{ border: "1px solid var(--border)" }}>
              {/* eslint-disable-next-line @next/next/no-img-element -- media URLs come from object storage */}
              <img src={photo.url ?? ""} alt={t("photoNumber", { number: at + 1 })} className="aspect-square w-full object-cover" />
              <div className="absolute inset-x-0 bottom-0 flex justify-between gap-1 p-1.5" style={{ background: "linear-gradient(transparent, rgba(0,0,0,.6))" }}>
                <span className="flex gap-1">
                  <button
                    type="button"
                    disabled={at === 0}
                    aria-label={t("moveEarlier", { number: at + 1 })}
                    onClick={() => move(at, at - 1)}
                    className="grid h-8 w-8 place-items-center rounded-full text-white disabled:opacity-30"
                  >
                    <span aria-hidden="true">‹</span>
                  </button>
                  <button
                    type="button"
                    disabled={at === draft.photos.length - 1}
                    aria-label={t("moveLater", { number: at + 1 })}
                    onClick={() => move(at, at + 1)}
                    className="grid h-8 w-8 place-items-center rounded-full text-white disabled:opacity-30"
                  >
                    <span aria-hidden="true">›</span>
                  </button>
                </span>
                <span className="flex gap-1">
                  <button
                    type="button"
                    aria-label={t("makeCover", { number: at + 1 })}
                    onClick={() =>
                      setDraft({
                        ...draft,
                        cover: photo,
                        photos: [
                          ...draft.photos.filter((other) => other.id !== photo.id),
                          ...(draft.cover ? [draft.cover] : []),
                        ].slice(0, MAX_PHOTOS),
                      })
                    }
                    className="grid h-8 w-8 place-items-center rounded-full text-white"
                  >
                    <span aria-hidden="true">★</span>
                  </button>
                  <button
                    type="button"
                    aria-label={t("removeNumber", { number: at + 1 })}
                    onClick={() => setDraft({ ...draft, photos: draft.photos.filter((other) => other.id !== photo.id) })}
                    className="grid h-8 w-8 place-items-center rounded-full text-white"
                  >
                    <span aria-hidden="true">✕</span>
                  </button>
                </span>
              </div>
            </li>
          ))}
          {Array.from({ length: uploading }, (_, at) => (
            <li key={`uploading-${at}`} className="grid aspect-square place-items-center rounded-2xl text-xs" style={{ border: "1px dashed var(--border)", color: "var(--dim)" }}>
              {t("uploading")}
            </li>
          ))}
          {draft.photos.length + uploading < MAX_PHOTOS ? (
            <li>
              <button
                type="button"
                onClick={() => galleryInput.current?.click()}
                className="grid aspect-square w-full place-items-center rounded-2xl text-2xl"
                style={{ border: "2px dashed var(--border)", color: "var(--muted)" }}
                aria-label={t("addPhotos")}
              >
                <span aria-hidden="true">+</span>
              </button>
            </li>
          ) : null}
        </ul>
        <input
          ref={galleryInput}
          type="file"
          accept="image/*"
          multiple
          hidden
          onChange={(event) => {
            void upload(Array.from(event.target.files ?? []), "gallery");
            event.target.value = "";
          }}
        />
      </section>
    </div>
  );
}

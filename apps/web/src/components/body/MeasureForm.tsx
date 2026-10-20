"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  BODY_CONSENTS_KEY,
  BODY_KEY,
  attachBodyPhoto,
  createBodySnapshot,
  fetchLatestBodyPhotos,
  grantHealthConsent,
  removeBodyPhoto,
  updateBodySnapshot,
  type BodyMetric,
  type BodyPhoto,
  type BodyPose,
  type BodySnapshot,
  type BodyVisibility,
  type WeightDisplay,
} from "@/api/body";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { ChoicePill, ErrorLine } from "@/components/community/Sheet";
import { BodyCamera } from "@/components/body/BodyCamera";
import { BodyPhotoView, Card, Eyebrow, PillButton, PrivacyLine, key } from "@/components/body/BodyBits";
import { MeasureHelpSheet, PhotoConsentSheet, WeightDisplaySheet } from "@/components/body/BodySheets";
import { bodyErrorMessage } from "@/components/body/errors";
import { useBodyPhotoUploads } from "@/components/body/use-body-photos";
import { useBodySettings, useBodySnapshots, useBodyToken, useHealthConsents, useUpdateBodySettings } from "@/components/body/use-body";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import {
  POSES,
  checkMeasure,
  formFields,
  formatNumber,
  fromLocalInput,
  initialValues,
  isSensitive,
  metricsPatch,
  shouldAskWeightDisplay,
  toLocalInput,
  unitOf,
} from "@/lib/body";

const VISIBILITIES: BodyVisibility[] = ["private", "coach_numbers", "coach_full"];
const ASKED_KEY = "milos:body:weight-display-asked";

function readAsked() {
  try {
    return window.localStorage.getItem(ASKED_KEY) === "1";
  } catch {
    return false;
  }
}

function writeAsked() {
  try {
    window.localStorage.setItem(ASKED_KEY, "1");
  } catch {
    // A private window: the question may come back once more.
  }
}

/**
 * Μέτρηση (mockup «measure», board 13 q3): three optional pose photos, then
 * the fields used last time first with last time's value as a faded hint,
 * «+ Άλλη μέτρηση», an editable date, «Πώς μετράω;», who sees it. Every field
 * is optional; a snapshot needs one value or one photo. Also edits one.
 */
export function MeasureForm({ snapshot }: { snapshot?: BodySnapshot }) {
  const t = useTranslations("Body");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const router = useRouter();
  const queryClient = useQueryClient();
  const token = useBodyToken();
  const settings = useBodySettings();
  const history = useBodySnapshots();
  const consents = useHealthConsents();
  const updateSettings = useUpdateBodySettings();
  const latestPhotos = useQuery({
    queryKey: [...BODY_KEY, "photos", "latest"],
    enabled: Boolean(token),
    queryFn: () => fetchLatestBodyPhotos(token!),
  });
  const uploads = useBodyPhotoUploads(token, settings.data?.photos);

  const previous = useMemo(() => {
    const list = history.data?.pages.flatMap((page) => page.snapshots) ?? [];
    return list.filter((item) => item.id !== snapshot?.id);
  }, [history.data, snapshot?.id]);
  const hintSource = snapshot ? null : (previous[0] ?? null);

  const [values, setValues] = useState<Partial<Record<BodyMetric, string>>>(() => (snapshot ? initialValues(snapshot.metrics, locale) : {}));
  const [opened, setOpened] = useState<BodyMetric[]>([]);
  const [takenAt, setTakenAt] = useState(() => toLocalInput(snapshot?.taken_at ?? new Date()));
  const [visibility, setVisibility] = useState<BodyVisibility | null>(snapshot?.visibility ?? null);
  const [notes, setNotes] = useState(snapshot?.notes ?? "");
  const [removed, setRemoved] = useState<string[]>([]);
  const [camera, setCamera] = useState<BodyPose | null>(null);
  const [consentFor, setConsentFor] = useState<BodyPose | null>(null);
  const [consentBusy, setConsentBusy] = useState(false);
  const [consentError, setConsentError] = useState<string | null>(null);
  const [declined, setDeclined] = useState(false);
  const [askWeight, setAskWeight] = useState(false);
  const [help, setHelp] = useState(false);
  const [showExtras, setShowExtras] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [touched, setTouched] = useState(false);

  if (settings.isPending || history.isPending) return <LoadingLine />;
  if (settings.isError) return <QueryProblem error={settings.error} onRetry={() => void settings.refetch()} />;

  const { catalog, settings: prefs } = settings.data;
  const units = snapshot?.units ?? prefs.units;
  const chosenVisibility = visibility ?? prefs.default_visibility;
  const { fields, extras } = formFields(snapshot ?? hintSource, opened);
  const existing = (pose: BodyPose): BodyPhoto | null =>
    snapshot?.photos.find((photo) => photo.pose === pose && !removed.includes(photo.id)) ?? null;
  const photoCount = POSES.filter((pose) => uploads.pending[pose] || existing(pose)).length;
  const check = checkMeasure(values, photoCount, catalog);
  const consented = consents.data?.some((consent) => consent.scope === "body_photos" && consent.active) ?? false;
  const ghostOf = (pose: BodyPose) => latestPhotos.data?.find((photo) => photo.pose === pose && photo.status === "ready")?.feed_url ?? null;

  function openSlot(pose: BodyPose) {
    if (!consented) {
      setConsentError(null);
      setConsentFor(pose);
      return;
    }
    setCamera(pose);
  }

  async function agree() {
    if (!token || !consentFor) return;
    setConsentBusy(true);
    setConsentError(null);
    try {
      const next = await grantHealthConsent(token, "body_photos");
      queryClient.setQueryData(BODY_CONSENTS_KEY, next);
      const pose = consentFor;
      setConsentFor(null);
      setDeclined(false);
      setCamera(pose);
    } catch (caught) {
      setConsentError(bodyErrorMessage(caught, t, tUi));
    } finally {
      setConsentBusy(false);
    }
  }

  async function chooseWeightDisplay(choice: WeightDisplay) {
    writeAsked();
    try {
      await updateSettings.mutateAsync({ weight_display: choice });
    } catch {
      // The choice can be made again in Ρυθμίσεις › Σώμα; saving the snapshot goes on.
    }
    setAskWeight(false);
    void save(true);
  }

  async function save(skipQuestion = false) {
    setTouched(true);
    if (!token || saving || !check.ok || uploads.busy) return;
    if (
      !skipQuestion &&
      !snapshot &&
      shouldAskWeightDisplay({
        typedWeight: check.metrics.weight !== undefined,
        weightDisplay: prefs.weight_display,
        history: previous,
        answered: readAsked(),
      })
    ) {
      setAskWeight(true);
      return;
    }
    setSaving(true);
    setError(null);
    const taken = fromLocalInput(takenAt) ?? new Date().toISOString();
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone || "Etc/UTC";
    try {
      let id: string;
      if (snapshot) {
        const patch = metricsPatch(snapshot.metrics, check.metrics);
        await updateBodySnapshot(token, snapshot.id, {
          ...(Object.keys(patch).length ? { metrics: patch } : {}),
          units,
          taken_at: taken,
          taken_tz: zone,
          visibility: chosenVisibility,
          notes: notes.trim() || null,
        });
        for (const photoId of removed) await removeBodyPhoto(token, snapshot.id, photoId);
        for (const item of uploads.ready) {
          const replaced = snapshot.photos.find((photo) => photo.pose === item.pose && !removed.includes(photo.id));
          if (replaced) await removeBodyPhoto(token, snapshot.id, replaced.id);
          await attachBodyPhoto(token, snapshot.id, item.mediaId, item.pose);
        }
        id = snapshot.id;
      } else {
        const created = await createBodySnapshot(token, {
          metrics: check.metrics,
          units,
          taken_at: taken,
          taken_tz: zone,
          visibility: chosenVisibility,
          ...(notes.trim() ? { notes: notes.trim() } : {}),
          ...(uploads.ready.length ? { photos: uploads.ready.map((item) => ({ media_id: item.mediaId, pose: item.pose })) } : {}),
        });
        id = created.id;
      }
      uploads.settle();
      await queryClient.invalidateQueries({ queryKey: BODY_KEY });
      void queryClient.invalidateQueries({ queryKey: ["my", "journal"] });
      router.push(snapshot ? `/journal/body/${id}` : "/journal/body");
    } catch (caught) {
      setError(bodyErrorMessage(caught, t, tUi));
      setSaving(false);
    }
  }

  const field = (metric: BodyMetric) => {
    const unit = unitOf(metric, catalog, units);
    const hintValue = hintSource?.metrics[metric];
    const fieldError = touched || values[metric] ? check.errors[metric] : undefined;
    const inputId = ["body-field", metric].join("-");
    return (
      <div key={metric} className="flex items-center gap-3 border-b py-2 last:border-b-0" style={{ borderColor: "var(--border)" }}>
        <label htmlFor={inputId} className="flex-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t(key("metric", metric))}
          {metric === "body_fat" ? <span className="ms-1 text-xs font-normal" style={{ color: "var(--dim)" }}>{t("optional")}</span> : null}
          {fieldError ? (
            <span role="alert" className="block text-xs font-normal" style={{ color: "var(--danger)" }}>
              {t(key("fieldError", fieldError))}
            </span>
          ) : null}
        </label>
        <input
          id={inputId}
          inputMode="decimal"
          autoComplete="off"
          value={values[metric] ?? ""}
          onChange={(event) => setValues((current) => ({ ...current, [metric]: event.target.value }))}
          placeholder={typeof hintValue === "number" ? formatNumber(hintValue, locale) : ""}
          aria-invalid={Boolean(fieldError)}
          aria-describedby={typeof hintValue === "number" ? `${inputId}-hint` : undefined}
          className="w-24 rounded-xl px-3 py-2 text-end text-base tabular-nums"
          style={{ background: "var(--panel-raised)", border: `1px solid ${fieldError ? "var(--danger)" : "var(--border)"}`, color: "var(--text)" }}
        />
        <span className="w-8 text-sm" style={{ color: "var(--dim)" }}>{unit}</span>
        {typeof hintValue === "number" ? (
          <span id={`${inputId}-hint`} className="sr-only">
            {t("lastTimeHint", { value: formatNumber(hintValue, locale), unit })}
          </span>
        ) : null}
        {isSensitive(metric) && prefs.weight_display === "hidden" ? (
          <span className="sr-only">{t("hiddenFieldNote")}</span>
        ) : null}
      </div>
    );
  };

  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        void save();
      }}
      noValidate
    >
      <Card label={t("photosLabel")}>
        <div className="flex items-center justify-between gap-2">
          <Eyebrow>{t("photosLabel")}</Eyebrow>
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("optional")}</span>
        </div>
        {declined ? (
          <div className="flex flex-wrap items-center justify-between gap-2 text-sm" style={{ color: "var(--muted)" }}>
            <span>{t("photosDeclined")}</span>
            <button type="button" className="font-semibold underline" onClick={() => setDeclined(false)}>{t("photosAddAnyway")}</button>
          </div>
        ) : (
          <div className="grid grid-cols-3 gap-2">
            {POSES.map((pose) => {
              const item = uploads.pending[pose];
              const current = existing(pose);
              const label = t(key("pose", pose));
              const filled = Boolean(item || current);
              return (
                <div key={pose} className="relative">
                  <button
                    type="button"
                    onClick={() => openSlot(pose)}
                    aria-label={filled ? t("retakePose", { pose: label }) : t("addPose", { pose: label })}
                    className="relative block aspect-[3/4] w-full overflow-hidden rounded-xl"
                    style={{ background: "linear-gradient(160deg, #3b332c, #1e1915)", border: "1px dashed rgba(255,255,255,0.35)" }}
                    data-testid={["pose-slot", pose].join("-")}
                    data-phase={item?.phase ?? (current ? "saved" : "empty")}
                  >
                    {item ? (
                      // eslint-disable-next-line @next/next/no-img-element -- a local object URL
                      <img src={item.previewUrl} alt="" className="h-full w-full object-cover" />
                    ) : current ? (
                      <BodyPhotoView photo={current} blur={prefs.blur_photos} label={label} size="thumb" className="h-full w-full" />
                    ) : null}
                    <span className="absolute inset-x-1 bottom-1 truncate text-start text-[11px] font-bold text-white">
                      {item?.phase === "uploading"
                        ? t("uploading")
                        : item?.phase === "failed"
                          ? t("uploadFailed")
                          : filled
                            ? t("poseDone", { pose: label })
                            : t("poseAdd", { pose: label })}
                    </span>
                  </button>
                  {filled ? (
                    <button
                      type="button"
                      onClick={() => {
                        if (item) uploads.remove(pose);
                        else if (current) setRemoved((ids) => [...ids, current.id]);
                      }}
                      aria-label={t("removePose", { pose: label })}
                      className="absolute end-1 top-1 inline-flex h-7 w-7 items-center justify-center rounded-full text-sm font-bold text-white"
                      style={{ background: "rgba(0,0,0,0.55)" }}
                    >
                      <span aria-hidden="true">×</span>
                    </button>
                  ) : null}
                </div>
              );
            })}
          </div>
        )}
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("photosHint")}</p>
        <PrivacyLine>{t("photosPrivate")}</PrivacyLine>
      </Card>

      <Card label={t("measurementsLabel")}>
        <div className="flex items-center justify-between gap-2">
          <Eyebrow>{t("measurementsLabel")}</Eyebrow>
          <button type="button" onClick={() => setHelp(true)} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
            {t("howToMeasure")}
          </button>
        </div>
        {hintSource ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("hintsExplain")}</p> : null}
        <div className="flex flex-col">{fields.map(field)}</div>
        {extras.length ? (
          showExtras ? (
            <div className="flex flex-wrap gap-1.5" role="group" aria-label={t("otherMeasure")}>
              {extras.map((metric) => (
                <button
                  key={metric}
                  type="button"
                  onClick={() => setOpened((current) => [...current, metric])}
                  className="min-h-9 rounded-full px-3 text-sm font-semibold"
                  style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  {t(key("metric", metric))}
                </button>
              ))}
            </div>
          ) : (
            <button type="button" onClick={() => setShowExtras(true)} className="self-start text-sm font-semibold" style={{ color: "var(--primary)" }}>
              {t("otherMeasure")}
            </button>
          )
        ) : null}
        {prefs.weight_display !== "number" ? (
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t(key("weightDisplayFormNote", prefs.weight_display))}</p>
        ) : null}
      </Card>

      <Card label={t("whenLabel")}>
        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("whenLabel")}
          <input
            type="datetime-local"
            value={takenAt}
            max={toLocalInput(new Date())}
            onChange={(event) => setTakenAt(event.target.value)}
            className="min-h-11 rounded-xl px-3"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </label>
        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("notesLabel")}
          <textarea
            value={notes}
            maxLength={2000}
            rows={2}
            onChange={(event) => setNotes(event.target.value)}
            placeholder={t("notesPlaceholder")}
            className="rounded-xl p-3 text-sm font-normal"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </label>
      </Card>

      <Card label={t("whoSees")}>
        <Eyebrow>{t("whoSees")}</Eyebrow>
        <div role="radiogroup" aria-label={t("whoSees")} className="flex flex-col gap-2">
          {VISIBILITIES.map((item) => (
            <ChoicePill key={item} selected={chosenVisibility === item} onSelect={() => setVisibility(item)} hint={t(key("visibilityHint", item))}>
              {t(key("visibility", item))}
            </ChoicePill>
          ))}
        </div>
      </Card>

      {touched && check.empty ? <ErrorLine message={t("needOne")} /> : null}
      {uploads.failed ? <ErrorLine message={t("uploadFailedLong")} /> : null}
      <ErrorLine message={error} />
      <div className="flex gap-2">
        <Link
          href={snapshot ? `/journal/body/${snapshot.id}` : "/journal/body"}
          className="flex min-h-12 flex-1 items-center justify-center rounded-2xl text-sm font-bold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("cancel")}
        </Link>
        <div className="flex flex-[2] flex-col">
          <PillButton type="submit" primary disabled={saving || uploads.busy}>
            {saving ? t("saving") : uploads.busy ? t("waitUploads") : snapshot ? t("saveChanges") : t("saveSnapshot")}
          </PillButton>
        </div>
      </div>

      {camera ? (
        <BodyCamera
          pose={camera}
          ghostUrl={ghostOf(camera)}
          onClose={() => setCamera(null)}
          onKeep={(blob) => {
            const pose = camera;
            setCamera(null);
            void uploads.add(pose, blob);
          }}
        />
      ) : null}
      {consentFor ? (
        <PhotoConsentSheet
          busy={consentBusy}
          error={consentError}
          onAgree={() => void agree()}
          onDecline={() => {
            setConsentFor(null);
            setDeclined(true);
          }}
        />
      ) : null}
      {askWeight ? (
        <WeightDisplaySheet busy={updateSettings.isPending} onChoose={(choice) => void chooseWeightDisplay(choice)} onClose={() => setAskWeight(false)} />
      ) : null}
      {help ? <MeasureHelpSheet onClose={() => setHelp(false)} /> : null}
    </form>
  );
}

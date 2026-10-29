"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { ApiError } from "@/api/client";
import {
  BOX_SCREENS_KEY,
  createBoxScreen,
  deleteBoxScreen,
  listBoxScreens,
  newBoxScreenPairingCode,
  pinBoxScreen,
  unpinBoxScreen,
  updateBoxScreen,
  type BoxScreen,
  type BoxScreenOverrideView,
  type BoxScreenPairingCode,
} from "@/api/box-screens";
import { listAdminLocations, type FacilityLocation } from "@/api/facility";
import { fetchSchedule, type ScheduleSlot } from "@/api/schedule";
import { useSession } from "@/components/session-provider";
import {
  Pill,
  StatusText,
  captionClass,
  captionStyle,
  dangerButtonStyle,
  inputClass,
  inputStyle,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
} from "@/components/staff/staff-ui";
import { TimeInput } from "@/components/ui/DateInput";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { FieldError } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { classesOnScreen, untilFromTime } from "@/lib/box-screen";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";
import { adminHref, useOrganizationSlug, useOrganizationTimeZone } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";
import { useHydrated, useNow } from "@/components/box-screen/useBoxScreen";
import { addDaysToKey, dateKeyInZone, formatInZone, startOfDayInZone } from "@/lib/zoned-time";

// Ρυθμίσεις › Οθόνες box (ADR-253, mockup s8 with the owner's override):
// add a screen for a branch, read its pairing code out to the TV, and choose
// what it shows: automatic, or one view pinned (optionally until a time).

const WHOLE_BOX = "__box";
const VIEWS: BoxScreenOverrideView[] = ["wod", "timer", "leaderboard", "bookings", "class"];
const PENDING_POLL_MS = 4000;

function errorCode(error: unknown) {
  return error instanceof ApiError ? error.payload.code ?? null : null;
}

export function BoxScreensSettings() {
  const t = useTranslations("BoxScreens");
  const ui = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [adding, setAdding] = useState(false);
  // The code on show, and when that screen had last paired before it (a change means the TV paired).
  const [code, setCode] = useState<{ screenId: string; pairedBefore: string | null; pairing: BoxScreenPairingCode } | null>(null);

  const locations = useQuery({
    queryKey: ["admin", "locations"],
    enabled: Boolean(token),
    staleTime: FRESHNESS.reference,
    queryFn: () => listAdminLocations(token),
  });
  const screens = useQuery({
    queryKey: BOX_SCREENS_KEY,
    enabled: Boolean(token),
    // While a code waits to be typed on a TV, watch for the TV to pair.
    refetchInterval: (query) =>
      query.state.data?.screens.some((screen) => !screen.paired && screen.pairing_expires_at) || code ? PENDING_POLL_MS : false,
    queryFn: () => listBoxScreens(token),
  });

  const branches = locations.data ?? [];
  const list = screens.data?.screens ?? [];
  const full = screens.data ? list.length >= screens.data.max_screens : false;

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-3xl flex-col gap-5">
        <header>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{t("eyebrow")}</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{t("title")}</h1>
          <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>{t("intro")}</p>
        </header>

        {screens.isPending ? <StatusText tone="muted">{t("loading")}</StatusText> : null}
        {screens.isError ? <StatusText tone="error">{localizeError(screens.error, ui)}</StatusText> : null}

        {list.map((screen) => (
          <ScreenCard key={screen.id} token={token} screen={screen} branches={branches} onCode={(pairing) => setCode({ screenId: screen.id, pairedBefore: screen.paired_at, pairing })} />
        ))}

        {screens.data ? (
          list.length === 0 ? (
            <section className="grid gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("connectTitle")}</h2>
              <p className="text-sm" style={{ color: "var(--muted)" }}>{t("connectHint")}</p>
              <button type="button" className={`${primaryButtonClass} justify-self-start`} style={primaryButtonStyle} data-testid="box-screen-add" onClick={() => setAdding(true)}>
                {t("connectTitle")}
              </button>
            </section>
          ) : full ? (
            <p className="text-sm" style={{ color: "var(--muted)" }}>{t("limitReached", { count: screens.data.max_screens })}</p>
          ) : (
            <button type="button" className={`${secondaryButtonClass} self-start`} style={secondaryButtonStyle} data-testid="box-screen-add" onClick={() => setAdding(true)}>
              {t("connectAnother")}
            </button>
          )
        ) : null}
      </div>

      {adding ? (
        <AddScreenDialog
          token={token}
          branches={branches}
          onClose={() => setAdding(false)}
          onCreated={(screen, pairing) => {
            setAdding(false);
            setCode({ screenId: screen.id, pairedBefore: null, pairing });
          }}
        />
      ) : null}
      {code ? (
        <PairingCodeDialog
          pairing={code.pairing}
          paired={list.some((screen) => screen.id === code.screenId && screen.paired && screen.paired_at !== code.pairedBefore)}
          onClose={() => setCode(null)}
        />
      ) : null}
    </main>
  );
}

function branchLabel(t: ReturnType<typeof useTranslations>, branches: FacilityLocation[], id: string | null) {
  if (!id) return t("wholeBox");
  return branches.find((branch) => branch.id === id)?.name ?? t("otherBranch");
}

function ScreenCard({
  token,
  screen,
  branches,
  onCode,
}: {
  token: string;
  screen: BoxScreen;
  branches: FacilityLocation[];
  onCode: (pairing: BoxScreenPairingCode) => void;
}) {
  const t = useTranslations("BoxScreens");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const queryClient = useQueryClient();
  const [choosing, setChoosing] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const refresh = () => queryClient.invalidateQueries({ queryKey: BOX_SCREENS_KEY });

  const newCode = useMutation({ mutationFn: () => newBoxScreenPairingCode(token, screen.id), onSuccess: (result) => { void refresh(); onCode(result.pairing_code); } });
  const unpin = useMutation({ mutationFn: () => unpinBoxScreen(token, screen.id), onSuccess: refresh });
  const remove = useMutation({ mutationFn: () => deleteBoxScreen(token, screen.id), onSuccess: refresh });

  const now = useNow(PENDING_POLL_MS);
  const pending = !screen.paired && screen.pairing_expires_at && Date.parse(screen.pairing_expires_at) > now;
  const override = screen.override;
  const viewName = (view: BoxScreenOverrideView) => t(`view.${view}`);
  const changedBy = screen.focus_changed?.by?.name;
  const failure = newCode.error ?? unpin.error ?? remove.error;

  return (
    <section className="grid gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid={`box-screen-${screen.id}`}>
      <div className="flex items-start gap-3">
        <TvGlyph />
        <div className="min-w-0 flex-1">
          <h2 className="truncate text-base font-bold" style={{ color: "var(--text)" }}>{screen.name}</h2>
          <p className="text-sm" style={{ color: "var(--muted)" }}>
            {screen.location_id ? t("followsBranch", { branch: branchLabel(t, branches, screen.location_id) }) : t("followsBox")}
          </p>
        </div>
        {screen.paired ? <Pill tone="success">{t("paired")}</Pill> : pending ? <Pill tone="warning">{t("waiting")}</Pill> : <Pill tone="neutral">{t("notPaired")}</Pill>}
        <MoreMenu
          label={t("moreFor", { name: screen.name })}
          testId={`box-screen-more-${screen.id}`}
          items={[
            { label: t("rename"), onSelect: () => setRenaming(true), testId: "box-screen-rename" },
            { label: t("newCode"), onSelect: () => newCode.mutate(), disabled: newCode.isPending, testId: "box-screen-new-code" },
          ]}
        />
      </div>

      <div className="flex flex-wrap items-center gap-2 rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)" }} data-testid="box-screen-focus">
        <div className="min-w-0 flex-1 text-sm">
          <span className="font-semibold" style={{ color: "var(--text)" }}>{t("shows")} </span>
          {override ? (
            <span style={{ color: "var(--text)" }}>
              {t("pinned", { view: viewName(override.view) })}
              {override.until ? ` · ${t("until", { time: formatInZone(override.until, zone, locale, "time") })}` : ""}
            </span>
          ) : (
            <span style={{ color: "var(--text)" }}>{t("automatic")}</span>
          )}
          {screen.focus_changed ? (
            <span className="block text-xs" style={{ color: "var(--muted)" }}>
              {changedBy
                ? t("changedBy", { name: changedBy, time: formatInZone(screen.focus_changed.at, zone, locale, "weekday-time") })
                : t("changedAt", { time: formatInZone(screen.focus_changed.at, zone, locale, "weekday-time") })}
            </span>
          ) : null}
        </div>
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} data-testid="box-screen-choose" onClick={() => setChoosing(true)}>
          {t("choose")}
        </button>
        {override ? (
          <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} data-testid="box-screen-auto" disabled={unpin.isPending} onClick={() => unpin.mutate()}>
            {t("backToAuto")}
          </button>
        ) : null}
      </div>

      {failure ? <StatusText tone="error">{localizeError(failure, ui)}</StatusText> : null}

      <button
        type="button"
        className={`${secondaryButtonClass} justify-self-start`}
        style={dangerButtonStyle}
        data-testid="box-screen-remove"
        disabled={remove.isPending}
        onClick={() => {
          if (window.confirm(t("removeConfirm", { name: screen.name }))) remove.mutate();
        }}
      >
        {t("remove")}
      </button>

      {choosing ? <ChooseViewDialog token={token} screen={screen} zone={zone} onClose={() => setChoosing(false)} onSaved={async () => { setChoosing(false); await refresh(); }} /> : null}
      {renaming ? <RenameDialog token={token} screen={screen} onClose={() => setRenaming(false)} onSaved={async () => { setRenaming(false); await refresh(); }} /> : null}
    </section>
  );
}

function TvGlyph() {
  return (
    <svg aria-hidden="true" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ color: "var(--text-soft)", flexShrink: 0, marginTop: 2 }}>
      <rect x="2" y="5" width="20" height="13" rx="2" />
      <path d="M8 21h8M12 18v3" />
    </svg>
  );
}

function AddScreenDialog({
  token,
  branches,
  onClose,
  onCreated,
}: {
  token: string;
  branches: FacilityLocation[];
  onClose: () => void;
  onCreated: (screen: BoxScreen, pairing: BoxScreenPairingCode) => void;
}) {
  const t = useTranslations("BoxScreens");
  const ui = useUiTranslations();
  const [name, setName] = useState("");
  const [branch, setBranch] = useState<string>(branches.length === 1 ? branches[0].id : WHOLE_BOX);
  const create = useMutation({
    mutationFn: () => createBoxScreen(token, { name: name.trim(), location_id: branch === WHOLE_BOX ? null : branch }),
    onSuccess: (result) => onCreated(result.screen, result.pairing_code),
  });
  const code = create.isError ? errorCode(create.error) : null;
  const nameError = code === "invalid_screen_name" ? t("errorName") : null;
  const branchError = code === "invalid_screen_branch" ? t("errorBranch") : null;
  const general = create.isError && !nameError && !branchError ? (code === "too_many_screens" ? t("errorTooMany") : localizeError(create.error, ui)) : null;
  const edited = <T,>(set: (value: T) => void) => (value: T) => {
    if (create.isError) create.reset();
    set(value);
  };
  const options = [...branches.map((location) => ({ id: location.id, label: location.name })), { id: WHOLE_BOX, label: t("wholeBox") }];

  return (
    <Dialog
      title={t("connectTitle")}
      size="md"
      testId="box-screen-add-dialog"
      error={general}
      onClose={onClose}
      onSubmit={(event) => {
        event.preventDefault();
        if (name.trim()) create.mutate();
      }}
      footer={
        <>
          <DialogButton onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" testId="box-screen-create" disabled={!name.trim() || create.isPending}>
            {t("continue")}
          </DialogButton>
        </>
      }
    >
      <div className="grid gap-4">
        <label className="block">
          <span className={captionClass} style={captionStyle}>{t("name")}</span>
          <input
            className={inputClass}
            style={{ ...inputStyle, border: fieldBorder(nameError, inputStyle.border as string | undefined) }}
            {...invalidFieldProps(nameError, "box-screen-error-name")}
            maxLength={60}
            placeholder={t("namePlaceholder")}
            value={name}
            data-testid="box-screen-name"
            onChange={(event) => edited(setName)(event.target.value)}
          />
          <FieldError id="box-screen-error-name">{nameError}</FieldError>
        </label>
        {branches.length > 0 ? (
          <fieldset className="grid gap-2" {...invalidFieldProps(branchError, "box-screen-error-branch")}>
            <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("where")}</legend>
            {options.map((option) => (
              <label
                key={option.id}
                className="flex min-h-11 items-center gap-3 rounded-2xl px-3"
                style={{ border: fieldBorder(branchError && branch === option.id ? branchError : null), background: branch === option.id ? "var(--panel-muted)" : "transparent" }}
              >
                <input type="radio" name="box-screen-branch" value={option.id} checked={branch === option.id} onChange={() => edited(setBranch)(option.id)} data-testid={`box-screen-branch-${option.id}`} />
                <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{option.label}</span>
              </label>
            ))}
            <FieldError id="box-screen-error-branch">{branchError}</FieldError>
          </fieldset>
        ) : null}
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("whereHint")}</p>
      </div>
    </Dialog>
  );
}

function PairingCodeDialog({ pairing, paired, onClose }: { pairing: BoxScreenPairingCode; paired: boolean; onClose: () => void }) {
  const t = useTranslations("BoxScreens");
  const host = useHydrated() ? window.location.host : "palee.app";

  return (
    <Dialog
      title={t("codeTitle")}
      size="md"
      testId="box-screen-code-dialog"
      onClose={onClose}
      footer={
        <DialogButton tone="primary" onClick={onClose} testId="box-screen-code-done">
          {t("done")}
        </DialogButton>
      }
    >
      <div className="grid justify-items-center gap-4 text-center">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("codeHint", { url: `${host}/tv` })}</p>
        <p className="font-mono text-4xl font-extrabold tracking-[0.14em]" style={{ color: "var(--text)" }} data-testid="box-screen-code">
          {pairing.code}
        </p>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("codeValid")}</p>
        {paired ? (
          <p role="status" className="text-sm font-semibold" style={{ color: "var(--success)" }} data-testid="box-screen-code-paired">
            {t("codePaired")}
          </p>
        ) : null}
      </div>
    </Dialog>
  );
}

function RenameDialog({ token, screen, onClose, onSaved }: { token: string; screen: BoxScreen; onClose: () => void; onSaved: () => Promise<unknown> }) {
  const t = useTranslations("BoxScreens");
  const ui = useUiTranslations();
  const [name, setName] = useState(screen.name);
  const save = useMutation({ mutationFn: () => updateBoxScreen(token, screen.id, { name: name.trim() }), onSuccess: onSaved });
  const nameError = save.isError ? (errorCode(save.error) === "invalid_screen_name" ? t("errorName") : null) : null;
  const general = save.isError && !nameError ? localizeError(save.error, ui) : null;

  return (
    <Dialog
      title={t("renameTitle")}
      size="md"
      testId="box-screen-rename-dialog"
      error={general}
      onClose={onClose}
      onSubmit={(event) => {
        event.preventDefault();
        if (name.trim()) save.mutate();
      }}
      footer={
        <>
          <DialogButton onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" testId="box-screen-rename-save" disabled={!name.trim() || save.isPending}>
            {t("save")}
          </DialogButton>
        </>
      }
    >
      <label className="block">
        <span className={captionClass} style={captionStyle}>{t("name")}</span>
        <input
          className={inputClass}
          style={{ ...inputStyle, border: fieldBorder(nameError, inputStyle.border as string | undefined) }}
          {...invalidFieldProps(nameError, "box-screen-error-rename")}
          maxLength={60}
          value={name}
          data-testid="box-screen-rename-name"
          onChange={(event) => {
            if (save.isError) save.reset();
            setName(event.target.value);
          }}
        />
        <FieldError id="box-screen-error-rename">{nameError}</FieldError>
      </label>
    </Dialog>
  );
}

function ChooseViewDialog({
  token,
  screen,
  zone,
  onClose,
  onSaved,
}: {
  token: string;
  screen: BoxScreen;
  zone: string | null;
  onClose: () => void;
  onSaved: () => Promise<unknown>;
}) {
  const t = useTranslations("BoxScreens");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const [view, setView] = useState<BoxScreenOverrideView>(screen.override?.view ?? "wod");
  const [slotId, setSlotId] = useState<string>(screen.override?.slot_id ?? "");
  const [until, setUntil] = useState<string>(screen.override?.until ? formatInZone(screen.override.until, zone, "en-GB", { hour: "2-digit", minute: "2-digit", hourCycle: "h23" }) : "");

  const now = useNow(60_000);
  const day = dateKeyInZone(now, zone);
  const classes = useQuery({
    queryKey: ["admin", "box-screens", "today-classes", day],
    enabled: view === "class",
    staleTime: FRESHNESS.live,
    queryFn: () =>
      fetchSchedule(token, {
        startAt: startOfDayInZone(day, zone).toISOString(),
        endAt: startOfDayInZone(addDaysToKey(day, 1), zone).toISOString(),
        days: 1,
        classTypeIds: [],
      }),
  });
  const slots: ScheduleSlot[] = classesOnScreen(classes.data?.slots ?? [], screen.location_id).sort(
    (a, b) => Date.parse(a.scheduled_at) - Date.parse(b.scheduled_at),
  );

  const save = useMutation({
    mutationFn: () =>
      pinBoxScreen(token, screen.id, {
        view,
        slot_id: view === "class" ? slotId || null : null,
        until: until ? untilFromTime(until, zone, Date.now()) : null,
      }),
    onSuccess: onSaved,
  });
  const refused = save.isError && errorCode(save.error) === "invalid_screen_override";
  const classError = refused && view === "class" ? t("errorClass") : null;
  const untilError = refused && view !== "class" ? t("errorUntil") : null;
  const general = save.isError && !refused ? localizeError(save.error, ui) : null;
  const edited = <T,>(set: (value: T) => void) => (value: T) => {
    if (save.isError) save.reset();
    set(value);
  };
  const ready = view !== "class" || Boolean(slotId);

  return (
    <Dialog
      title={t("chooseTitle", { name: screen.name })}
      size="md"
      testId="box-screen-choose-dialog"
      error={general}
      onClose={onClose}
      onSubmit={(event) => {
        event.preventDefault();
        if (ready) save.mutate();
      }}
      footer={
        <>
          <DialogButton onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" testId="box-screen-pin" disabled={!ready || save.isPending}>
            {t("pin")}
          </DialogButton>
        </>
      }
    >
      <div className="grid gap-4">
        <fieldset className="grid gap-2">
          <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("showOnScreen")}</legend>
          {VIEWS.map((option) => (
            <label key={option} className="flex min-h-11 items-center gap-3 rounded-2xl px-3" style={{ background: view === option ? "var(--panel-muted)" : "transparent" }}>
              <input type="radio" name="box-screen-view" value={option} checked={view === option} onChange={() => edited(setView)(option)} data-testid={`box-screen-view-${option}`} />
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`view.${option}`)}</span>
            </label>
          ))}
        </fieldset>

        {view === "class" ? (
          <label className="block">
            <span className={captionClass} style={captionStyle}>{t("classLabel")}</span>
            {classes.isPending ? (
              <StatusText tone="muted">{t("loading")}</StatusText>
            ) : slots.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--muted)" }}>{t("noClassesToday")}</p>
            ) : (
              <Select
                className={inputClass}
                style={{ ...inputStyle, border: fieldBorder(classError, inputStyle.border as string | undefined) }}
                {...invalidFieldProps(classError, "box-screen-error-class")}
                value={slotId}
                placeholder={t("classPlaceholder")}
                onValueChange={edited(setSlotId)}
                data-testid="box-screen-class"
              >
                {slots.map((slot) => (
                  <option key={slot.id} value={slot.id}>
                    {`${formatInZone(slot.scheduled_at, zone, locale, "time")} ${slot.name}`}
                  </option>
                ))}
              </Select>
            )}
            <FieldError id="box-screen-error-class">{classError}</FieldError>
          </label>
        ) : null}

        <label className="block">
          <span className={captionClass} style={captionStyle}>{t("untilLabel")}</span>
          <TimeInput
            className={inputClass}
            style={{ ...inputStyle, border: fieldBorder(untilError, inputStyle.border as string | undefined) }}
            {...invalidFieldProps(untilError, "box-screen-error-until")}
            value={until}
            step={300}
            placeholder={t("untilPlaceholder")}
            onValueChange={edited(setUntil)}
            data-testid="box-screen-until"
          />
          <FieldError id="box-screen-error-until">{untilError}</FieldError>
          <span className="mt-1 block text-xs" style={{ color: "var(--muted)" }}>{t("untilHint")}</span>
        </label>
      </div>
    </Dialog>
  );
}

/** The settings entry for Οθόνες box, next to the branches. */
export function BoxScreensSettingsLink() {
  const t = useTranslations("BoxScreens");
  const slug = useOrganizationSlug();
  return (
    <Link
      href={adminHref("/admin/settings/box-screens", slug)}
      data-testid="box-screens-settings-link"
      className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("title")}</span>
        <span className="text-sm" style={{ color: "var(--muted)" }}>{t("navHint")}</span>
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
    </Link>
  );
}

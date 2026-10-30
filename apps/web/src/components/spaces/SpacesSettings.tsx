"use client";

import Link from "next/link";
import { useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { listAdminLocations, type FacilityLocation } from "@/api/facility";
import {
  archiveSpace,
  completeFloorPlanUpload,
  createFloorPlan,
  createSpace,
  deleteFloorPlan,
  deleteSpaceUnavailability,
  fetchSpace,
  fetchSpaces,
  makeSpaceUnavailable,
  putSpaceSettings,
  requestFloorPlanUpload,
  restoreSpace,
  updateFloorPlan,
  updateSpace,
  type FloorPlan,
  type Space,
  type SpaceInput,
} from "@/api/spaces";
import { useSession } from "@/components/session-provider";
import { FloorPlanCanvas, type PlanArea } from "@/components/spaces/FloorPlanCanvas";
import { RoomPhotosEditor } from "@/components/spaces/RoomPhotosEditor";
import { groupByBranch, spacesOnPlan, upcomingWindow, windowReady, type Point } from "@/components/spaces/floor-plan";
import {
  StaffPanel,
  StatusText,
  Pill,
  captionClass,
  captionStyle,
  inputClass,
  inputStyle,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  dangerButtonStyle,
} from "@/components/staff/staff-ui";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { DateTimeInput } from "@/components/ui/DateInput";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { FieldError } from "@/components/ui/ErrorNotice";
import { fieldBorder, formErrorsFrom, invalidFieldProps } from "@/lib/form-errors";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { preparePhoto } from "@/lib/media-files";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug, useOrganizationTimeZone } from "@/lib/organization-slug";
import { putPresigned } from "@/lib/presigned-upload";
import { can } from "@/lib/role-navigation";
import { dateTimeLocalToIso, formatInZone } from "@/lib/zoned-time";

export const SPACES_KEY = ["staff", "spaces"] as const;
const ALL = "__all";
const WHOLE_GYM = "__gym";

type Rights = { manage: boolean; details: boolean; unavailable: boolean };

/** Ρυθμίσεις › Χώροι (ADR-202): each branch's spaces, floor plans and unavailability. */
export function SpacesSettings() {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const { membership } = useSelectedMembershipRole();
  const rights: Rights = {
    manage: can(membership, "manage_spaces"),
    details: can(membership, "manage_spaces") || can(membership, "edit_space_details"),
    unavailable: can(membership, "manage_spaces") || can(membership, "set_space_unavailable"),
  };

  const [branch, setBranch] = useState<string>(ALL);
  const [showArchived, setShowArchived] = useState(false);
  const [editing, setEditing] = useState<Space | "new" | null>(null);
  const [unavailableFor, setUnavailableFor] = useState<Space | null>(null);
  const [detailId, setDetailId] = useState<string | null>(null);

  const locations = useQuery({ queryKey: ["admin", "locations"], enabled: Boolean(token), queryFn: () => listAdminLocations(token) });
  const spaces = useQuery({
    queryKey: [...SPACES_KEY, { archived: showArchived }],
    enabled: Boolean(token),
    queryFn: () => fetchSpaces(token, { includeArchived: showArchived }),
  });
  const refresh = () => queryClient.invalidateQueries({ queryKey: SPACES_KEY });

  const archive = useMutation({
    mutationFn: (space: Space) => (space.archived_at ? restoreSpace(token, space.id) : archiveSpace(token, space.id)),
    onSuccess: refresh,
  });

  const branches = locations.data ?? [];
  const branchName = (id: string | null) => (id ? branches.find((location) => location.id === id)?.name ?? t("unknownBranch") : t("wholeGym"));
  const order = branch === ALL ? [...branches.map((location) => location.id), null] : [branch === WHOLE_GYM ? null : branch];
  const groups = groupByBranch(spaces.data?.spaces ?? [], order).filter((group) => branch === ALL || group.locationId === (branch === WHOLE_GYM ? null : branch));

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-5xl flex-col gap-6">
        <header className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{t("eyebrow")}</p>
            <h1 className="mt-2 text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{t("title")}</h1>
            <p className="mt-2 max-w-2xl text-sm" style={{ color: "var(--muted)" }}>{t("intro")}</p>
          </div>
          {rights.manage ? (
            <button type="button" className={primaryButtonClass} style={primaryButtonStyle} data-testid="space-add" onClick={() => setEditing("new")}>
              {t("add")}
            </button>
          ) : null}
        </header>

        <div className="flex flex-wrap items-end gap-3">
          <label className="block min-w-48">
            <span className={captionClass} style={captionStyle}>{t("branch")}</span>
            <Select className={inputClass} style={inputStyle} value={branch} onValueChange={setBranch} data-testid="spaces-branch-filter">
              <option value={ALL}>{t("allBranches")}</option>
              {branches.map((location) => (
                <option key={location.id} value={location.id}>{location.name}</option>
              ))}
              <option value={WHOLE_GYM}>{t("wholeGym")}</option>
            </Select>
          </label>
          <label className="flex min-h-11 items-center gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
            <input type="checkbox" checked={showArchived} onChange={(event) => setShowArchived(event.target.checked)} />
            {t("showArchived")}
          </label>
        </div>

        {spaces.isPending ? <StatusText tone="muted">{t("loading")}</StatusText> : null}
        {spaces.isError ? <StatusText tone="error">{localizeError(spaces.error, ui)}</StatusText> : null}
        {archive.isError ? <StatusText tone="error">{localizeError(archive.error, ui)}</StatusText> : null}

        {spaces.data && rights.manage ? (
          <ClassPlansToggle token={token} on={spaces.data.settings?.floor_plans_in_classes ?? false} onChanged={refresh} />
        ) : null}

        {spaces.data
          ? groups.map((group) => (
              <BranchSpaces
                key={group.locationId ?? WHOLE_GYM}
                token={token}
                locationId={group.locationId}
                title={branchName(group.locationId)}
                spaces={group.items}
                plans={(spaces.data.floor_plans ?? []).filter((plan) => (plan.location_id ?? null) === group.locationId)}
                rights={rights}
                plansInClasses={spaces.data.settings?.floor_plans_in_classes ?? false}
                onRefresh={refresh}
                onOpen={setDetailId}
                onEdit={setEditing}
                onUnavailable={setUnavailableFor}
                onArchive={(space) => {
                  if (space.archived_at || window.confirm(t("archiveConfirm", { name: space.name }))) archive.mutate(space);
                }}
              />
            ))
          : null}
      </div>

      {editing ? (
        <SpaceForm
          token={token}
          space={editing === "new" ? null : editing}
          branches={branches}
          defaultBranch={branch === ALL || branch === WHOLE_GYM ? null : branch}
          plans={spaces.data?.floor_plans ?? []}
          rights={rights}
          onClose={() => setEditing(null)}
          onSaved={async () => {
            setEditing(null);
            await refresh();
          }}
        />
      ) : null}
      {unavailableFor ? (
        <UnavailableForm
          token={token}
          space={unavailableFor}
          onClose={() => setUnavailableFor(null)}
          onSaved={refresh}
        />
      ) : null}
      {detailId ? (
        <SpaceDetailDialog token={token} spaceId={detailId} rights={rights} branchName={branchName} onClose={() => setDetailId(null)} onChanged={refresh} />
      ) : null}
    </main>
  );
}

function BranchSpaces({
  token,
  locationId,
  title,
  spaces,
  plans,
  rights,
  plansInClasses,
  onRefresh,
  onOpen,
  onEdit,
  onUnavailable,
  onArchive,
}: {
  token: string;
  locationId: string | null;
  title: string;
  spaces: Space[];
  plans: FloorPlan[];
  rights: Rights;
  plansInClasses: boolean;
  onRefresh: () => Promise<unknown>;
  onOpen: (id: string) => void;
  onEdit: (space: Space) => void;
  onUnavailable: (space: Space) => void;
  onArchive: (space: Space) => void;
}) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const [planId, setPlanId] = useState<string | null>(null);
  const [drawFor, setDrawFor] = useState<string | null>(null);
  const plan = plans.find((item) => item.id === planId) ?? plans[0] ?? null;
  const active = spaces.filter((space) => !space.archived_at);
  const groupId = `spaces-${locationId ?? "gym"}`;

  const draw = useMutation({
    mutationFn: ({ spaceId, points }: { spaceId: string; points: Point[] }) => updateSpace(token, spaceId, { floor_plan_id: plan!.id, area: { points } }),
    onSuccess: async () => {
      setDrawFor(null);
      await onRefresh();
    },
  });
  const showFloor = useMutation({
    mutationFn: ({ id, shown }: { id: string; shown: boolean }) => updateFloorPlan(token, id, { shown_in_classes: shown }),
    onSuccess: onRefresh,
  });
  const removePlan = useMutation({
    mutationFn: (id: string) => deleteFloorPlan(token, id),
    onSuccess: async () => {
      setPlanId(null);
      await onRefresh();
    },
  });

  const areas: PlanArea[] = plan
    ? spacesOnPlan(active, plan.id).map((space) => ({
        id: space.id,
        label: space.name,
        points: space.area!.points,
        tone: space.id === drawFor ? "selected" : (space.unavailability ?? []).some((window) => isNow(window)) ? "due" : "default",
      }))
    : [];
  const drawing = drawFor ? active.find((space) => space.id === drawFor) : null;

  return (
    <StaffPanel
      labelledBy={groupId}
      eyebrow={t("branch")}
      title={title}
      actions={rights.manage ? <FloorPlanUpload token={token} locationId={locationId} sortOrder={plans.length} onDone={onRefresh} /> : null}
    >
      {plans.length > 0 ? (
        <div className="mb-5 flex flex-col gap-3" data-testid={`${groupId}-plans`}>
          <div className="flex flex-wrap items-center gap-2" role="tablist" aria-label={t("floorPlans")}>
            {plans.map((item) => (
              <button
                key={item.id}
                type="button"
                role="tab"
                aria-selected={plan?.id === item.id}
                className={secondaryButtonClass}
                style={plan?.id === item.id ? primaryButtonStyle : secondaryButtonStyle}
                onClick={() => setPlanId(item.id)}
              >
                {item.name}
              </button>
            ))}
            {rights.manage && plan ? (
              <button
                type="button"
                className={secondaryButtonClass}
                style={dangerButtonStyle}
                disabled={removePlan.isPending}
                onClick={() => {
                  if (window.confirm(t("deletePlanConfirm", { name: plan.name }))) removePlan.mutate(plan.id);
                }}
              >
                {t("deletePlan")}
              </button>
            ) : null}
          </div>
          {/* ADR-290: with more than one floor, each floor can stay out of the classes. */}
          {rights.manage && plansInClasses && plans.length > 1 ? (
            <fieldset className="flex flex-wrap items-center gap-x-4 gap-y-2 text-sm" data-testid={`${groupId}-floors-in-classes`}>
              <legend className="mb-1 text-xs" style={{ color: "var(--dim)" }}>{t("floorsInClasses")}</legend>
              {plans.map((item) => (
                <label key={item.id} className="flex min-h-9 items-center gap-2" style={{ color: "var(--text-soft)" }}>
                  <input
                    type="checkbox"
                    checked={item.shown_in_classes}
                    disabled={showFloor.isPending}
                    data-testid={`floor-in-classes-${item.id}`}
                    onChange={(event) => showFloor.mutate({ id: item.id, shown: event.target.checked })}
                  />
                  {item.name}
                </label>
              ))}
            </fieldset>
          ) : null}
          {showFloor.isError ? <StatusText tone="error">{localizeError(showFloor.error, ui)}</StatusText> : null}
          {plan ? (
            <>
              {drawing ? (
                <p className="text-sm" role="status" style={{ color: "var(--primary)" }}>
                  {t("drawHint", { name: drawing.name })}{" "}
                  <button type="button" className="underline" onClick={() => setDrawFor(null)}>{t("cancel")}</button>
                </p>
              ) : null}
              <FloorPlanCanvas
                testId={`floor-plan-${plan.id}`}
                imageUrl={plan.image_url}
                alt={t("planAlt", { name: plan.name })}
                areas={areas}
                drawing={Boolean(drawing)}
                onAreaClick={onOpen}
                onDraw={(points) => drawing && draw.mutate({ spaceId: drawing.id, points })}
              />
              {draw.isError ? <StatusText tone="error">{localizeError(draw.error, ui)}</StatusText> : null}
            </>
          ) : null}
        </div>
      ) : rights.manage ? (
        <p className="mb-4 text-sm" style={{ color: "var(--muted)" }}>{t("noPlans")}</p>
      ) : null}
      {removePlan.isError ? <StatusText tone="error">{localizeError(removePlan.error, ui)}</StatusText> : null}

      {spaces.length === 0 ? (
        <StatusText tone="muted">{t("empty")}</StatusText>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2">
          {spaces.map((space) => {
            const unavailableNow = (space.unavailability ?? []).some((window) => isNow(window));
            return (
              <li
                key={space.id}
                data-testid={`space-${space.id}`}
                className="flex flex-col gap-2 rounded-2xl p-4"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", opacity: space.archived_at ? 0.7 : 1 }}
              >
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <button type="button" className="text-start font-semibold underline-offset-2 hover:underline" style={{ color: "var(--text)" }} onClick={() => onOpen(space.id)}>
                    {space.name}
                  </button>
                  <span className="flex gap-1">
                    {space.archived_at ? <Pill tone="neutral">{t("archived")}</Pill> : null}
                    {unavailableNow ? <Pill tone="warning">{t("unavailableNow")}</Pill> : null}
                    {space.area ? <Pill tone="primary">{t("onPlan")}</Pill> : null}
                  </span>
                </div>
                {space.description ? <p className="text-sm" style={{ color: "var(--muted)" }}>{space.description}</p> : null}
                <div className="flex flex-wrap gap-2">
                  {rights.details && !space.archived_at ? (
                    <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => onEdit(space)}>
                      {t("edit")}
                    </button>
                  ) : null}
                  {rights.unavailable && !space.archived_at ? (
                    <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => onUnavailable(space)}>
                      {t("makeUnavailable")}
                    </button>
                  ) : null}
                  {rights.manage && plan && !space.archived_at ? (
                    <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} data-testid={`space-draw-${space.id}`} onClick={() => setDrawFor(space.id)}>
                      {space.area && space.floor_plan_id === plan.id ? t("redraw") : t("draw")}
                    </button>
                  ) : null}
                  {rights.manage ? (
                    <button type="button" className={secondaryButtonClass} style={space.archived_at ? secondaryButtonStyle : dangerButtonStyle} onClick={() => onArchive(space)}>
                      {space.archived_at ? t("restore") : t("archive")}
                    </button>
                  ) : null}
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </StaffPanel>
  );
}

function isNow(window: { starts_at: string; ends_at: string }, now = new Date()) {
  return new Date(window.starts_at).getTime() <= now.getTime() && upcomingWindow(window, now);
}

function FloorPlanUpload({ token, locationId, sortOrder, onDone }: { token: string; locationId: string | null; sortOrder: number; onDone: () => Promise<unknown> }) {
  const t = useTranslations("Spaces");
  const input = useRef<HTMLInputElement>(null);
  const [name, setName] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [open, setOpen] = useState(false);
  const upload = useMutation({
    mutationFn: async () => {
      const prepared = await preparePhoto(file!, "original");
      const reserved = await requestFloorPlanUpload(token, { content_type: prepared.contentType as "image/jpeg" | "image/webp", byte_size: prepared.blob.size });
      await putPresigned(reserved.upload_url, prepared.blob, reserved.required_headers);
      await completeFloorPlanUpload(token, reserved.media_id);
      return createFloorPlan(token, { location_id: locationId, name: name.trim(), media_id: reserved.media_id, sort_order: sortOrder });
    },
    onSuccess: async () => {
      setOpen(false);
      setName("");
      setFile(null);
      await onDone();
    },
  });

  return (
    <>
      <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} data-testid={`plan-upload-${locationId ?? "gym"}`} onClick={() => setOpen(true)}>
        {t("addPlan")}
      </button>
      {open ? (
        <Dialog
          title={t("addPlan")}
          description={t("addPlanHint")}
          size="md"
          onClose={() => setOpen(false)}
          onSubmit={(event) => {
            event.preventDefault();
            if (file && name.trim()) upload.mutate();
          }}
          footer={
            <>
              <DialogButton onClick={() => setOpen(false)}>{t("cancel")}</DialogButton>
              <DialogButton type="submit" tone="primary" disabled={!file || !name.trim() || upload.isPending}>
                {upload.isPending ? t("uploading") : t("upload")}
              </DialogButton>
            </>
          }
        >
          <div className="flex flex-col gap-3">
            <label className="block">
              <span className={captionClass} style={captionStyle}>{t("planName")}</span>
              <input className={inputClass} style={inputStyle} maxLength={80} value={name} placeholder={t("planNamePlaceholder")} onChange={(event) => setName(event.target.value)} />
            </label>
            <label className="block">
              <span className={captionClass} style={captionStyle}>{t("planImage")}</span>
              <input
                ref={input}
                type="file"
                accept="image/*"
                className="mt-1 block w-full text-sm"
                data-testid="plan-file"
                onChange={(event) => setFile(event.target.files?.[0] ?? null)}
              />
            </label>
            {upload.isError ? <UploadError error={upload.error} /> : null}
          </div>
        </Dialog>
      ) : null}
    </>
  );
}

function UploadError({ error }: { error: unknown }) {
  const ui = useUiTranslations();
  const t = useTranslations("Spaces");
  return <StatusText tone="error">{error instanceof Error && error.name === "PresignedUploadError" ? t("uploadFailed") : localizeError(error, ui)}</StatusText>;
}

/** ADR-214: the space form's fields, as the API names them. */
const SPACE_FIELDS = ["name", "description", "directions", "location_id", "floor_plan_id", "tasks"] as const;
type SpaceField = (typeof SPACE_FIELDS)[number];

function SpaceForm({
  token,
  space,
  branches,
  defaultBranch,
  plans,
  rights,
  onClose,
  onSaved,
}: {
  token: string;
  space: Space | null;
  branches: FacilityLocation[];
  defaultBranch: string | null;
  plans: FloorPlan[];
  rights: Rights;
  onClose: () => void;
  onSaved: () => Promise<unknown>;
}) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const [name, setName] = useState(space?.name ?? "");
  const [description, setDescription] = useState(space?.description ?? "");
  const [directions, setDirections] = useState(space?.directions ?? "");
  const [locationId, setLocationId] = useState<string>(space ? space.location_id ?? WHOLE_GYM : defaultBranch ?? WHOLE_GYM);
  const [tasks, setTasks] = useState((space?.tasks ?? []).join("\n"));
  const [planId, setPlanId] = useState<string>(space?.floor_plan_id ?? "");
  const branchPlans = plans.filter((plan) => (plan.location_id ?? WHOLE_GYM) === locationId);

  const save = useMutation({
    mutationFn: () => {
      const details: SpaceInput = { name: name.trim(), description: description.trim() || null, directions: directions.trim() || null };
      const body: SpaceInput = rights.manage
        ? {
            ...details,
            location_id: locationId === WHOLE_GYM ? null : locationId,
            tasks: tasks.split("\n").map((task) => task.trim()).filter(Boolean),
            floor_plan_id: planId || null,
            ...(planId ? {} : { area: null }),
          }
        : details;
      return space ? updateSpace(token, space.id, body) : createSpace(token, body);
    },
    onSuccess: onSaved,
  });
  // ADR-214: a refused save marks its fields; editing any field clears it.
  const errors = save.isError ? formErrorsFrom(save.error, ui, SPACE_FIELDS) : null;
  const edited = <T,>(set: (value: T) => void) => (value: T) => {
    if (save.isError) save.reset();
    set(value);
  };
  const field = (key: SpaceField) => ({
    style: errors?.fields[key] ? { ...inputStyle, border: fieldBorder(errors.fields[key]) } : inputStyle,
    ...invalidFieldProps(errors?.fields[key], `space-error-${key}`),
  });

  return (
    <Dialog
      title={space ? t("editTitle", { name: space.name }) : t("add")}
      error={errors?.message}
      size="lg"
      testId="space-form"
      onClose={onClose}
      onSubmit={(event) => {
        event.preventDefault();
        if (name.trim()) save.mutate();
      }}
      footer={
        <>
          <DialogButton onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" testId="space-save" disabled={!name.trim() || save.isPending}>
            {t("save")}
          </DialogButton>
        </>
      }
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="block sm:col-span-2">
          <span className={captionClass} style={captionStyle}>{t("name")}</span>
          <input className={inputClass} {...field("name")} maxLength={80} value={name} data-testid="space-name" onChange={(event) => edited(setName)(event.target.value)} />
          <FieldError id="space-error-name">{errors?.fields.name}</FieldError>
        </label>
        <label className="block sm:col-span-2">
          <span className={captionClass} style={captionStyle}>{t("description")}</span>
          <textarea className={inputClass} {...field("description")} rows={2} maxLength={2000} value={description} onChange={(event) => edited(setDescription)(event.target.value)} />
          <FieldError id="space-error-description">{errors?.fields.description}</FieldError>
        </label>
        <label className="block sm:col-span-2">
          <span className={captionClass} style={captionStyle}>{t("directions")}</span>
          <textarea
            className={inputClass}
            {...field("directions")}
            rows={2}
            maxLength={2000}
            value={directions}
            placeholder={t("directionsPlaceholder")}
            onChange={(event) => edited(setDirections)(event.target.value)}
          />
          <FieldError id="space-error-directions">{errors?.fields.directions}</FieldError>
        </label>
        {rights.manage ? (
          <>
            <label className="block">
              <span className={captionClass} style={captionStyle}>{t("branch")}</span>
              <Select
                className={inputClass}
                {...field("location_id")}
                value={locationId}
                data-testid="space-branch"
                onValueChange={edited((value: string) => {
                  setLocationId(value);
                  setPlanId("");
                })}
              >
                <option value={WHOLE_GYM}>{t("wholeGym")}</option>
                {branches.map((location) => (
                  <option key={location.id} value={location.id}>{location.name}</option>
                ))}
              </Select>
              <FieldError id="space-error-location_id">{errors?.fields.location_id}</FieldError>
            </label>
            <label className="block">
              <span className={captionClass} style={captionStyle}>{t("floorPlan")}</span>
              <Select className={inputClass} {...field("floor_plan_id")} value={planId} onValueChange={edited(setPlanId)}>
                <option value="">{t("noPlan")}</option>
                {branchPlans.map((plan) => (
                  <option key={plan.id} value={plan.id}>{plan.name}</option>
                ))}
              </Select>
              <FieldError id="space-error-floor_plan_id">{errors?.fields.floor_plan_id}</FieldError>
            </label>
            <label className="block sm:col-span-2">
              <span className={captionClass} style={captionStyle}>{t("tasks")}</span>
              <textarea className={inputClass} {...field("tasks")} rows={3} value={tasks} onChange={(event) => edited(setTasks)(event.target.value)} />
              <FieldError id="space-error-tasks">{errors?.fields.tasks}</FieldError>
            </label>
          </>
        ) : null}
      </div>
    </Dialog>
  );
}

function UnavailableForm({ token, space, onClose, onSaved }: { token: string; space: Space; onClose: () => void; onSaved: () => Promise<unknown> }) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const zone = useOrganizationTimeZone();
  const locale = useUiLocale();
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [reason, setReason] = useState("");
  const startIso = startsAt ? dateTimeLocalToIso(startsAt, zone) : null;
  const endIso = endsAt ? dateTimeLocalToIso(endsAt, zone) : null;
  const ready = windowReady(startIso, endIso);
  const save = useMutation({
    mutationFn: () => makeSpaceUnavailable(token, space.id, { starts_at: startIso!, ends_at: endIso!, reason: reason.trim() || null }),
    onSuccess: onSaved,
  });
  const affected = save.data?.affected_classes ?? null;

  return (
    <Dialog
      title={t("makeUnavailableTitle", { name: space.name })}
      description={t("makeUnavailableHint")}
      size="md"
      testId="space-unavailable-form"
      onClose={onClose}
      onSubmit={(event) => {
        event.preventDefault();
        if (ready && !save.isSuccess) save.mutate();
      }}
      footer={
        save.isSuccess ? (
          <DialogButton tone="primary" onClick={onClose}>{t("done")}</DialogButton>
        ) : (
          <>
            <DialogButton onClick={onClose}>{t("cancel")}</DialogButton>
            <DialogButton type="submit" tone="primary" testId="space-unavailable-save" disabled={!ready || save.isPending}>
              {t("makeUnavailable")}
            </DialogButton>
          </>
        )
      }
    >
      {save.isSuccess ? (
        <div className="flex flex-col gap-2" data-testid="space-unavailable-result">
          <StatusText tone="success">{t("unavailableSaved")}</StatusText>
          {affected && affected.length > 0 ? (
            <>
              <p className="text-sm" style={{ color: "var(--warning)" }}>{t("affectedClasses", { count: affected.length })}</p>
              <ul className="text-sm" style={{ color: "var(--text-soft)" }}>
                {affected.map((item) => (
                  <li key={item.id}>{item.name} · {formatInZone(item.scheduled_at, zone, locale, "day-time")}</li>
                ))}
              </ul>
            </>
          ) : null}
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block">
            <span className={captionClass} style={captionStyle}>{t("from")}</span>
            <DateTimeInput className={inputClass} style={inputStyle} value={startsAt} onValueChange={setStartsAt} data-testid="unavailable-from" />
          </label>
          <label className="block">
            <span className={captionClass} style={captionStyle}>{t("to")}</span>
            <DateTimeInput className={inputClass} style={inputStyle} value={endsAt} onValueChange={setEndsAt} data-testid="unavailable-to" />
          </label>
          <label className="block sm:col-span-2">
            <span className={captionClass} style={captionStyle}>{t("reason")}</span>
            <input className={inputClass} style={inputStyle} maxLength={500} value={reason} placeholder={t("reasonPlaceholder")} data-testid="unavailable-reason" onChange={(event) => setReason(event.target.value)} />
          </label>
          {startsAt && endsAt && !ready ? (
            <p className="text-sm sm:col-span-2" style={{ color: "var(--danger)" }}>{t("endAfterStart")}</p>
          ) : null}
          {save.isError ? (
            <div className="sm:col-span-2">
              <StatusText tone="error">{localizeError(save.error, ui)}</StatusText>
            </div>
          ) : null}
        </div>
      )}
    </Dialog>
  );
}

function SpaceDetailDialog({
  token,
  spaceId,
  rights,
  branchName,
  onClose,
  onChanged,
}: {
  token: string;
  spaceId: string;
  rights: Rights;
  branchName: (id: string | null) => string;
  onClose: () => void;
  onChanged: () => Promise<unknown>;
}) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const key = useMemo(() => [...SPACES_KEY, "detail", spaceId], [spaceId]);
  const detail = useQuery({ queryKey: key, enabled: Boolean(token), queryFn: () => fetchSpace(token, spaceId) });
  const remove = useMutation({
    mutationFn: (windowId: string) => deleteSpaceUnavailability(token, spaceId, windowId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: key });
      await onChanged();
    },
  });
  const space = detail.data;

  return (
    <Dialog title={space?.name ?? t("loading")} eyebrow={space ? branchName(space.location_id ?? null) : undefined} size="lg" variant="drawer" testId="space-detail" onClose={onClose}>
      {detail.isPending ? <StatusText tone="muted">{t("loading")}</StatusText> : null}
      {detail.isError ? <StatusText tone="error">{localizeError(detail.error, ui)}</StatusText> : null}
      {space ? (
        <div className="flex flex-col gap-5">
          {space.description ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{space.description}</p> : null}
          {space.directions ? (
            <section>
              <h3 className={captionClass} style={captionStyle}>{t("directions")}</h3>
              <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>{space.directions}</p>
            </section>
          ) : null}

          <RoomPhotosEditor
            token={token}
            spaceId={space.id}
            photos={space.photos ?? []}
            points={space.points ?? []}
            canEdit={rights.details && !space.archived_at}
            queryKey={key}
          />

          <section data-testid="space-detail-unavailability">
            <h3 className={captionClass} style={captionStyle}>{t("unavailability")}</h3>
            {space.unavailability.length === 0 ? (
              <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{t("alwaysAvailable")}</p>
            ) : (
              <ul className="mt-2 flex flex-col gap-2">
                {space.unavailability.map((window) => (
                  <li key={window.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl px-3 py-2 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                    <span style={{ color: "var(--text)" }}>
                      {formatInZone(window.starts_at, zone, locale, "day-time")} → {formatInZone(window.ends_at, zone, locale, "day-time")}
                      {window.reason ? <span style={{ color: "var(--muted)" }}> · {window.reason}</span> : null}
                    </span>
                    {rights.unavailable ? (
                      <button type="button" className={secondaryButtonClass} style={dangerButtonStyle} disabled={remove.isPending} onClick={() => remove.mutate(window.id)}>
                        {t("removeWindow")}
                      </button>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
            {remove.isError ? <StatusText tone="error">{localizeError(remove.error, ui)}</StatusText> : null}
          </section>

          <section data-testid="space-detail-classes">
            <h3 className={captionClass} style={captionStyle}>{t("upcomingClasses")}</h3>
            {space.classes.length === 0 ? (
              <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{t("noClasses")}</p>
            ) : (
              <ul className="mt-2 flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
                {space.classes.map((item) => (
                  <li key={item.id} className="flex items-center justify-between gap-2 py-2 text-sm">
                    <span style={{ color: "var(--text)" }}>{item.name}</span>
                    <span style={{ color: "var(--dim)" }}>{formatInZone(item.scheduled_at, zone, locale, "day-time")}</span>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section data-testid="space-detail-equipment">
            <h3 className={captionClass} style={captionStyle}>{t("equipment")}</h3>
            {space.equipment.length === 0 ? (
              <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{t("noEquipment")}</p>
            ) : (
              <ul className="mt-2 flex flex-col gap-1 text-sm">
                {space.equipment.map((item) => (
                  <li key={item.machine_id} className="flex justify-between gap-2" style={{ color: "var(--text)" }}>
                    <span>{item.name}</span>
                    <span style={{ color: "var(--dim)" }}>× {item.quantity}</span>
                  </li>
                ))}
              </ul>
            )}
            <Link href={adminHref("/admin/inventory", slug)} className="mt-2 inline-block text-sm underline" style={{ color: "var(--primary)" }}>
              {t("manageEquipment")}
            </Link>
          </section>
        </div>
      ) : null}
    </Dialog>
  );
}

/**
 * ADR-290: one switch for the whole gym. On, the people who see a class open
 * «Δες στην κάτοψη» in its details: its room coloured on the floor plan,
 * with the room's photos.
 */
function ClassPlansToggle({ token, on, onChanged }: { token: string; on: boolean; onChanged: () => Promise<unknown> }) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const save = useMutation({
    mutationFn: (next: boolean) => putSpaceSettings(token, { floor_plans_in_classes: next }),
    onSuccess: onChanged,
  });
  return (
    <section className="rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <label className="flex items-start gap-3">
        <input
          type="checkbox"
          className="mt-1"
          checked={on}
          disabled={save.isPending}
          data-testid="plans-in-classes"
          onChange={(event) => save.mutate(event.target.checked)}
        />
        <span className="flex flex-col">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("plansInClasses")}</span>
          <span className="text-sm" style={{ color: "var(--muted)" }}>{t("plansInClassesHint")}</span>
        </span>
      </label>
      {save.isError ? <StatusText tone="error">{localizeError(save.error, ui)}</StatusText> : null}
    </section>
  );
}

/** The settings entry for Χώροι, next to the branches. */
export function SpacesSettingsLink() {
  const t = useTranslations("Spaces");
  const slug = useOrganizationSlug();
  return (
    <Link
      href={adminHref("/admin/spaces", slug)}
      data-testid="spaces-settings-link"
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

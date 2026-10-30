"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { placeMachine, type Machine } from "@/api/inventory";
import { fetchSpaces } from "@/api/spaces";
import { placementSummary } from "@/components/spaces/cleaning-today";
import { FloorPlanCanvas } from "@/components/spaces/FloorPlanCanvas";
import { validArea } from "@/components/spaces/floor-plan";
import { StatusText, captionClass, captionStyle, inputClass, inputStyle, secondaryButtonClass, secondaryButtonStyle, dangerButtonStyle } from "@/components/staff/staff-ui";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

const SPACE_RIGHTS = ["view_spaces", "manage_spaces", "edit_space_details", "set_space_unavailable"];

type Row = { space_id: string; quantity: number; positions?: number[][] };

/**
 * Where a machine stands (ADR-202): how many in which space, the rest
 * unassigned. Seen by whoever sees the spaces; changed by whoever manages
 * the inventory or the spaces.
 */
export function MachinePlacement({ token, machine, machinesKey }: { token: string; machine: Machine; machinesKey: readonly unknown[] }) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const { membership } = useSelectedMembershipRole();
  const visible = SPACE_RIGHTS.some((capability) => can(membership, capability));
  const canPlace = can(membership, "manage_inventory") || can(membership, "manage_spaces");
  const spaces = useQuery({ queryKey: ["staff", "spaces", { archived: false }], enabled: visible && Boolean(token), queryFn: () => fetchSpaces(token, {}), staleTime: 60_000 });
  const placements: Row[] = machine.placements ?? [];
  const [editing, setEditing] = useState(false);
  const [rows, setRows] = useState<Row[]>(placements);
  const [pinning, setPinning] = useState<number | null>(null);
  const save = useMutation({
    mutationFn: () =>
      placeMachine(
        token,
        machine.id,
        rows.filter((row) => row.space_id && row.quantity > 0).map((row) => ({ ...row, positions: (row.positions ?? []).slice(0, row.quantity) })),
      ),
    onSuccess: async () => {
      setEditing(false);
      await Promise.all([queryClient.invalidateQueries({ queryKey: machinesKey }), queryClient.invalidateQueries({ queryKey: ["staff", "spaces"] })]);
    },
  });

  if (!visible) return null;
  const all = spaces.data?.spaces ?? [];
  const nameOf = (id: string) => all.find((space) => space.id === id)?.name ?? "—";
  // ADR-290: a space drawn on a floor plan can take a pin per item.
  const planOf = (id: string) => {
    const space = all.find((item) => item.id === id);
    const plan = space?.floor_plan_id ? (spaces.data?.floor_plans ?? []).find((item) => item.id === space.floor_plan_id) : null;
    return space && plan && validArea(space.area) ? { space, plan, area: space.area } : null;
  };
  const setPositions = (index: number, positions: number[][]) =>
    setRows((current) => current.map((item, at) => (at === index ? { ...item, positions } : item)));
  const unassigned = machine.unassigned ?? placementSummary(machine.quantity, placements).unassigned;
  const draft = placementSummary(machine.quantity, rows);

  return (
    <section className="flex flex-col gap-2" data-testid={`placement-${machine.id}`}>
      <h4 className={captionClass} style={captionStyle}>{t("placementTitle")}</h4>
      {editing ? (
        <div className="flex flex-col gap-2">
          {rows.map((row, index) => (
            <div key={index} className="flex flex-wrap items-end gap-2">
              <label className="block min-w-40 flex-1">
                <span className="sr-only">{t("placementSpace")}</span>
                <Select
                  className={inputClass}
                  style={inputStyle}
                  value={row.space_id}
                  placeholder={t("placementPickSpace")}
                  data-testid={`placement-space-${index}`}
                  onValueChange={(value) => setRows((current) => current.map((item, at) => (at === index ? { ...item, space_id: value } : item)))}
                >
                  {all.map((space) => (
                    <option key={space.id} value={space.id}>{space.name}</option>
                  ))}
                </Select>
              </label>
              <label className="block w-24">
                <span className="sr-only">{t("placementQuantity")}</span>
                <input
                  className={inputClass}
                  style={inputStyle}
                  type="number"
                  min={1}
                  max={machine.quantity}
                  step={1}
                  value={Number.isFinite(row.quantity) ? row.quantity : ""}
                  data-testid={`placement-quantity-${index}`}
                  onChange={(event) => {
                    const quantity = event.target.value === "" ? Number.NaN : Math.round(Number(event.target.value));
                    setRows((current) => current.map((item, at) => (at === index ? { ...item, quantity } : item)));
                  }}
                />
              </label>
              {planOf(row.space_id) ? (
                <button
                  type="button"
                  className={secondaryButtonClass}
                  style={pinning === index ? { ...secondaryButtonStyle, borderColor: "var(--primary)", color: "var(--primary)" } : secondaryButtonStyle}
                  aria-pressed={pinning === index}
                  data-testid={`placement-pin-${index}`}
                  onClick={() => setPinning(pinning === index ? null : index)}
                >
                  📍 {t("placementPins", { count: (row.positions ?? []).length })}
                </button>
              ) : null}
              <button type="button" className={secondaryButtonClass} style={dangerButtonStyle} onClick={() => setRows((current) => current.filter((_, at) => at !== index))}>
                {t("placementRemove")}
              </button>
              {pinning === index && planOf(row.space_id) ? (
                <PinEditor
                  row={row}
                  target={planOf(row.space_id)!}
                  onChange={(positions) => setPositions(index, positions)}
                />
              ) : null}
            </div>
          ))}
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              className={secondaryButtonClass}
              style={secondaryButtonStyle}
              disabled={all.length === 0}
              onClick={() => setRows((current) => [...current, { space_id: "", quantity: Math.max(1, draft.unassigned) }])}
            >
              {t("placementAdd")}
            </button>
            <span className="text-xs" style={{ color: draft.fits ? "var(--dim)" : "var(--danger)" }}>
              {draft.fits ? t("placementUnassigned", { count: draft.unassigned }) : t("placementTooMany", { owned: machine.quantity })}
            </span>
          </div>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setEditing(false)}>
              {t("cancel")}
            </button>
            <button
              type="button"
              className={secondaryButtonClass}
              style={secondaryButtonStyle}
              data-testid={`placement-save-${machine.id}`}
              disabled={!draft.fits || rows.some((row) => !row.space_id || !(row.quantity > 0)) || save.isPending}
              onClick={() => save.mutate()}
            >
              {t("save")}
            </button>
          </div>
          {save.isError ? <StatusText tone="error">{localizeError(save.error, ui)}</StatusText> : null}
        </div>
      ) : (
        <>
          {placements.length === 0 ? (
            <p className="text-sm" style={{ color: "var(--muted)" }}>{t("placementNone")}</p>
          ) : (
            <ul className="flex flex-col gap-1 text-sm">
              {placements.map((row) => (
                <li key={row.space_id} className="flex justify-between gap-2" style={{ color: "var(--text)" }}>
                  <span>{nameOf(row.space_id)}</span>
                  <span style={{ color: "var(--dim)" }}>× {row.quantity}</span>
                </li>
              ))}
            </ul>
          )}
          {unassigned > 0 ? (
            <p className="text-xs" data-testid={`placement-unassigned-${machine.id}`} style={{ color: "var(--warning)" }}>
              {t("placementUnassigned", { count: unassigned })}
            </p>
          ) : null}
          {canPlace ? (
            <div>
              <button
                type="button"
                className={secondaryButtonClass}
                style={secondaryButtonStyle}
                data-testid={`placement-edit-${machine.id}`}
                onClick={() => {
                  setRows(placements);
                  setEditing(true);
                }}
              >
                {t("placementEdit")}
              </button>
            </div>
          ) : null}
        </>
      )}
    </section>
  );
}

/** ADR-290: tap the plan to pin where each item of the row stands; tap a pin to take it off. */
function PinEditor({
  row,
  target,
  onChange,
}: {
  row: Row;
  target: { space: { id: string; name: string }; plan: { id: string; name: string; image_url?: string | null }; area: { points: number[][] } };
  onChange: (positions: number[][]) => void;
}) {
  const t = useTranslations("Spaces");
  const positions = row.positions ?? [];
  const room = Math.max(0, (Number.isFinite(row.quantity) ? row.quantity : 0) - positions.length);
  return (
    <div className="flex w-full flex-col gap-1" data-testid={`pin-editor-${target.space.id}`}>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{room > 0 ? t("placementPinHint", { count: room }) : t("placementPinFull")}</p>
      <FloorPlanCanvas
        imageUrl={target.plan.image_url}
        alt={t("planAlt", { name: target.plan.name })}
        areas={[{ id: target.space.id, label: target.space.name, points: target.area.points, tone: "selected" }]}
        pins={positions.map((at, index) => ({ id: String(index), at, label: t("placementPinRemove") }))}
        onPin={room > 0 ? (at) => onChange([...positions, at]) : undefined}
        onPinClick={(id) => onChange(positions.filter((_, index) => String(index) !== id))}
      />
    </div>
  );
}

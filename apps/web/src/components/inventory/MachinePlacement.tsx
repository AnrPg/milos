"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { placeMachine, type Machine } from "@/api/inventory";
import { fetchSpaces } from "@/api/spaces";
import { placementSummary } from "@/components/spaces/cleaning-today";
import { StatusText, captionClass, captionStyle, inputClass, inputStyle, secondaryButtonClass, secondaryButtonStyle, dangerButtonStyle } from "@/components/staff/staff-ui";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

const SPACE_RIGHTS = ["view_spaces", "manage_spaces", "edit_space_details", "set_space_unavailable"];

type Row = { space_id: string; quantity: number };

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
  const save = useMutation({
    mutationFn: () => placeMachine(token, machine.id, rows.filter((row) => row.space_id && row.quantity > 0)),
    onSuccess: async () => {
      setEditing(false);
      await Promise.all([queryClient.invalidateQueries({ queryKey: machinesKey }), queryClient.invalidateQueries({ queryKey: ["staff", "spaces"] })]);
    },
  });

  if (!visible) return null;
  const all = spaces.data?.spaces ?? [];
  const nameOf = (id: string) => all.find((space) => space.id === id)?.name ?? "—";
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
              <button type="button" className={secondaryButtonClass} style={dangerButtonStyle} onClick={() => setRows((current) => current.filter((_, at) => at !== index))}>
                {t("placementRemove")}
              </button>
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

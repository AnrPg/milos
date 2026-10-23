"use client";

import { useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useTranslations } from "next-intl";

import { AnatomyFigure } from "@/components/anatomy/AnatomyFigure";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import type { AnatomyHighlights, AnatomyPickLevel, AnatomyRole } from "@/lib/anatomy/figure";
import { groupOf, muscleNode, type MuscleNodeId } from "@/lib/anatomy/taxonomy";
import { searchKey, searchMuscleTree } from "@/lib/wod-goals/goals";

import { MuscleChip, RoleLegend, Segmented } from "./GoalChips";
import { Select } from "@/components/ui/Select";
import { useHideBottomNav } from "@/components/nav/bottom-nav-visibility";

export type PickerEntry = { id: MuscleNodeId; role: AnatomyRole };

const LONG_PRESS_MS = 450;

/** Next role in `options`, then off (null). */
export function cycleEntry(options: readonly AnatomyRole[], role: AnatomyRole | undefined): AnatomyRole | null {
  if (!role) return options[0];
  const index = options.indexOf(role);
  return index < 0 || index === options.length - 1 ? null : options[index + 1];
}

export function setEntry(entries: readonly PickerEntry[], id: MuscleNodeId, role: AnatomyRole | null): PickerEntry[] {
  if (role === null) return entries.filter((entry) => entry.id !== id);
  if (entries.some((entry) => entry.id === id)) return entries.map((entry) => (entry.id === id ? { id, role } : entry));
  return [...entries, { id, role }];
}

/**
 * Applies a tap on the body: a group is added in the first role; a head
 * (second tap in a group) replaces its group in the list, keeping its role.
 * A long press cycles the role instead.
 */
export function applyPick(
  entries: readonly PickerEntry[],
  options: readonly AnatomyRole[],
  nodeId: MuscleNodeId,
  level: AnatomyPickLevel,
  longPress: boolean,
): PickerEntry[] {
  const current = entries.find((entry) => entry.id === nodeId)?.role;
  if (longPress) return setEntry(entries, nodeId, cycleEntry(options, current));
  if (current) return [...entries];
  if (level === "head") {
    const group = groupOf(nodeId);
    const groupEntry = entries.find((entry) => entry.id === group);
    if (groupEntry) return entries.map((entry) => (entry.id === group ? { id: nodeId, role: groupEntry.role } : entry));
  }
  return setEntry(entries, nodeId, options[0]);
}

/**
 * Full-screen muscle picker (Q2): the interactive body (front/back, drag to
 * turn, tap a group, tap again for a head, which the camera frames) and a
 * searchable list by region, switchable with «Σώμα · Λίστα» over one shared
 * selection. Roles change by long press, by the role control for the
 * selected muscle, or by the role selector of a list row.
 */
export function MusclePickerSheet({
  title,
  hint,
  entries,
  roleOptions,
  backdrop = {},
  onChange,
  onClose,
}: {
  title: string;
  hint: string;
  entries: PickerEntry[];
  /** Goals: primary, secondary, stabilizer. Felt: felt. */
  roleOptions: AnatomyRole[];
  /** Drawn under the selection (the goals while marking what was felt). */
  backdrop?: AnatomyHighlights;
  onChange: (entries: PickerEntry[]) => void;
  onClose: () => void;
}) {
  // A full-screen surface: the member app's bottom bar steps aside.
  useHideBottomNav();
  const t = useTranslations("WodGoals");
  const anatomy = useTranslations("Anatomy");
  const labelId = useId();
  const dialog = useModalFocusTrap<HTMLElement>(onClose);
  const [tab, setTab] = useState<"body" | "list">("body");
  const [view, setView] = useState<"front" | "back">("front");
  const [selected, setSelected] = useState<MuscleNodeId | null>(entries[0]?.id ?? null);
  const [focus, setFocus] = useState<MuscleNodeId | null>(null);
  const [query, setQuery] = useState("");
  const pointerDownAt = useRef<number | null>(null);
  const name = (id: MuscleNodeId) => anatomy(`muscle.${id}`);
  const roleLabel = (role: AnatomyRole) => (role === "felt" ? t("picker.felt") : t(`role.${role}`));

  const highlights = useMemo(() => {
    const next: AnatomyHighlights = { ...backdrop };
    for (const entry of entries) next[entry.id] = entry.role;
    return next;
  }, [backdrop, entries]);

  function handlePick(nodeId: MuscleNodeId, level: AnatomyPickLevel) {
    const longPress = pointerDownAt.current !== null && Date.now() - pointerDownAt.current >= LONG_PRESS_MS;
    pointerDownAt.current = null;
    onChange(applyPick(entries, roleOptions, nodeId, level, longPress));
    setSelected(nodeId);
    setFocus(level === "head" ? nodeId : null);
  }

  const selectedRole = entries.find((entry) => entry.id === selected)?.role ?? null;
  const normalizedQuery = searchKey(query.trim());
  const tree = useMemo(
    () => searchMuscleTree((id) => !normalizedQuery || searchKey(anatomy(`muscle.${id}`)).includes(normalizedQuery)),
    [anatomy, normalizedQuery],
  );

  return createPortal(
    <section
      ref={dialog}
      role="dialog"
      aria-modal="true"
      aria-labelledby={labelId}
      className="fixed inset-0 z-(--z-fullscreen) flex flex-col"
      style={{ background: "var(--bg)", color: "var(--text)" }}
    >
      <header className="flex items-center justify-between gap-3 border-b px-4 py-3" style={{ borderColor: "var(--border)" }}>
        <h2 id={labelId} className="text-lg font-extrabold">{title}</h2>
        <button
          type="button"
          onClick={onClose}
          className="min-h-11 rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("picker.done")}
        </button>
      </header>

      <div className="flex flex-col gap-2 px-4 pt-3">
        <Segmented
          ariaLabel={title}
          value={tab}
          onChange={setTab}
          options={[
            { value: "body", label: t("picker.body") },
            { value: "list", label: t("picker.list") },
          ]}
        />
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-4 py-3">
        {tab === "body" ? (
          <div className="flex flex-col gap-2">
            <p className="text-xs" style={{ color: "var(--text-soft)" }}>{hint}</p>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="w-48">
                <Segmented
                  ariaLabel={t("picker.body")}
                  value={view}
                  onChange={(next) => {
                    setView(next);
                    setFocus(null);
                  }}
                  options={[
                    { value: "front", label: t("picker.front") },
                    { value: "back", label: t("picker.back") },
                  ]}
                />
              </div>
              {focus ? (
                <button type="button" className="min-h-9 text-xs font-semibold" style={{ color: "var(--primary-strong, var(--primary))" }} onClick={() => setFocus(null)}>
                  {t("picker.resetZoom")}
                </button>
              ) : null}
            </div>
            <div onPointerDownCapture={() => (pointerDownAt.current = Date.now())}>
              <AnatomyFigure highlights={highlights} view={view} interactive onPick={handlePick} focus={focus} size="full" />
            </div>
            <RoleLegend roles={roleOptions} />
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            <input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t("picker.search")}
              aria-label={t("picker.search")}
              className="min-h-11 w-full rounded-xl border px-3 text-sm outline-none"
              style={{ background: "var(--panel)", borderColor: "var(--border)", color: "var(--text)" }}
            />
            {tree.length === 0 ? (
              <p className="py-6 text-center text-sm" style={{ color: "var(--dim)" }}>{t("picker.noResults")}</p>
            ) : (
              tree.map(({ region, rows }) => (
                <section key={region}>
                  <h3 className="mb-1 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{name(region)}</h3>
                  <ul className="flex flex-col divide-y rounded-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)", borderColor: "var(--border)" }}>
                    {rows.map((row) => {
                      const role = entries.find((entry) => entry.id === row.id)?.role ?? null;
                      return (
                        <li key={row.id} className="flex min-h-11 items-center justify-between gap-2 px-3 py-1.5" style={{ borderColor: "var(--border)" }}>
                          <span className={`min-w-0 truncate text-sm ${row.kind === "head" ? "ps-4" : "font-semibold"}`}>{name(row.id)}</span>
                          {roleOptions.length === 1 ? (
                            <button
                              type="button"
                              aria-pressed={role !== null}
                              aria-label={t("picker.roleFor", { muscle: name(row.id) })}
                              onClick={() => {
                                onChange(setEntry(entries, row.id, role ? null : roleOptions[0]));
                                setSelected(row.id);
                              }}
                              className="min-h-9 shrink-0 rounded-full px-3 text-xs font-semibold"
                              style={{
                                background: role ? "color-mix(in srgb, var(--anatomy-felt) 22%, var(--panel))" : "var(--panel-raised, var(--card))",
                                border: `1px solid ${role ? "var(--anatomy-felt)" : "var(--border)"}`,
                              }}
                            >
                              {role ? `✓ ${roleLabel(roleOptions[0])}` : t("picker.add")}
                            </button>
                          ) : (
                            <Select
                              aria-label={t("picker.roleFor", { muscle: name(row.id) })}
                              value={role ?? ""}
                              onValueChange={(value) => {
                                onChange(setEntry(entries, row.id, (value || null) as AnatomyRole | null));
                                setSelected(row.id);
                              }}
                              className="min-h-9 shrink-0 rounded-lg border px-2 text-xs"
                              style={{ background: "var(--bg)", borderColor: "var(--border)", color: "var(--text)" }}
                            >
                              <option value="">—</option>
                              {roleOptions.map((option) => (
                                <option key={option} value={option}>{roleLabel(option)}</option>
                              ))}
                            </Select>
                          )}
                        </li>
                      );
                    })}
                  </ul>
                </section>
              ))
            )}
          </div>
        )}
      </div>

      <footer className="flex flex-col gap-2 border-t px-4 pt-3" style={{ borderColor: "var(--border)", paddingBottom: "max(0.75rem, env(safe-area-inset-bottom))" }}>
        {selected && muscleNode(selected) && roleOptions.length > 1 ? (
          <Segmented
            ariaLabel={t("picker.roleFor", { muscle: name(selected) })}
            value={selectedRole ?? "off"}
            onChange={(value) => onChange(setEntry(entries, selected, value === "off" ? null : (value as AnatomyRole)))}
            options={[...roleOptions.map((role) => ({ value: role as string, label: roleLabel(role) })), { value: "off", label: t("role.off") }]}
          />
        ) : null}
        {entries.length === 0 ? (
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("picker.selectedNone")}</p>
        ) : (
          <div className="flex max-h-28 flex-wrap gap-1.5 overflow-y-auto">
            {entries.map((entry) => (
              <MuscleChip
                key={entry.id}
                label={name(entry.id)}
                role={entry.role}
                selected={entry.id === selected}
                onPress={() => {
                  setSelected(entry.id);
                  if (tab === "body") setFocus(entry.id);
                }}
                removeLabel={t("removeMuscle", { muscle: name(entry.id) })}
                onRemove={() => onChange(setEntry(entries, entry.id, null))}
              />
            ))}
          </div>
        )}
      </footer>
    </section>,
    document.body,
  );
}

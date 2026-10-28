"use client";

import { useState } from "react";

import { ALL_ROLES, type RoleName } from "@/api/roles";
import { RoleLabel } from "@/components/semantic-label";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";

const STAFF: readonly string[] = ["owner", "admin", "coach", "front_desk", "accountant", "janitor"];

/**
 * A role set as chips (ADR-099, ADR-219): the roles in `editable` toggle,
 * the rest of the held roles show locked. Save and Cancel appear once the
 * set differs from `current`.
 */
export function RoleChipsEditor({
  current,
  editable,
  pending,
  error,
  onSave,
  label,
}: {
  current: readonly string[];
  editable: readonly RoleName[];
  pending: boolean;
  error?: string | null;
  onSave: (roles: RoleName[]) => void;
  label?: string;
}) {
  const i18n = useUiTranslations();
  const [draft, setDraft] = useState<RoleName[] | null>(null);
  const roles = draft ?? (current as RoleName[]);
  const changed = draft !== null && [...draft].sort().join() !== [...current].sort().join();
  const visible = ALL_ROLES.filter((role) => editable.includes(role) || current.includes(role));
  const toggle = (role: RoleName) =>
    setDraft(roles.includes(role) ? roles.filter((item) => item !== role) : [...roles, role]);

  return (
    <div className="space-y-3">
      <div role="group" aria-label={label} className="flex flex-wrap gap-2">
        {visible.map((role) => {
          const selected = roles.includes(role);
          return (
            <button
              key={role}
              type="button"
              aria-pressed={selected}
              disabled={!editable.includes(role) || pending}
              onClick={() => toggle(role)}
              className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
              style={{
                background: selected ? "var(--primary)" : "var(--panel-muted)",
                border: `1px ${STAFF.includes(role) ? "solid" : "dashed"} var(--border)`,
                color: selected ? "var(--primary-contrast)" : "var(--text-soft)",
              }}
            >
              <RoleLabel role={role} />
            </button>
          );
        })}
      </div>
      {changed ? (
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            disabled={roles.length === 0 || pending}
            onClick={() => onSave(roles)}
            className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--text)", color: "var(--bg)" }}
          >
            {pending ? i18n("loading33ce417") : i18n("saveRoles")}
          </button>
          <button
            type="button"
            onClick={() => setDraft(null)}
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            {i18n("cancel77dfd21")}
          </button>
        </div>
      ) : null}
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
    </div>
  );
}

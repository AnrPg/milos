"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { listAdminLocations } from "@/api/facility";
import type { RoleName } from "@/api/roles";
import { BranchScopePicker } from "@/components/admin/users/BranchScopePicker";
import { grantableRoles } from "@/components/admin/users/MemberRolesEditor";
import { RoleLabel } from "@/components/semantic-label";
import { hasSeveralBranches, membershipLocationScope, type LocationScope } from "@/lib/location-scope";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { membershipRoles } from "@/lib/role-navigation";

const STAFF_ROLES: RoleName[] = ["owner", "admin", "coach", "front_desk", "accountant", "janitor"];

export type StaffInvite = { roles: RoleName[]; scope: LocationScope | null };

/** The staff roles the signed-in person may invite (ADR-099 ceiling). */
export function useInvitableStaffRoles(): RoleName[] {
  const { membership } = useSelectedMembershipRole();
  return grantableRoles(membershipRoles(membership)).filter((role) => STAFF_ROLES.includes(role));
}

/** The invitation body for a staff link (ADR-186): a role set and, when chosen, branches. */
export function staffInvitationBody(invite: StaffInvite) {
  const scope = invite.roles.includes("owner") ? null : invite.scope;
  return {
    role: invite.roles[0],
    roles: invite.roles,
    ...(scope === null ? {} : scope === "all" ? { all_locations: true } : { all_locations: false, location_ids: scope }),
  };
}

/**
 * Staff roles and branches of one invitation link, e.g. «Coach @ Κηφισιά +
 * Μαρούσι». Without a branch choice the link carries the inviter's own
 * branches; a business with one branch sees no branch picker.
 */
export function StaffInviteFields({
  token,
  value,
  onChange,
}: {
  token: string;
  value: StaffInvite;
  onChange: (value: StaffInvite) => void;
}) {
  const t = useTranslations("BranchScope");
  const { membership } = useSelectedMembershipRole();
  const invitable = useInvitableStaffRoles();
  const actorScope = membershipLocationScope(membership);
  const locations = useQuery({
    queryKey: ["admin", "locations"],
    enabled: invitable.length > 0,
    queryFn: () => listAdminLocations(token),
  });
  const showBranches =
    !value.roles.includes("owner") && (hasSeveralBranches(locations.data) || actorScope !== "all");
  const scope = value.scope ?? actorScope;

  const toggle = (role: RoleName) =>
    onChange({
      ...value,
      roles: value.roles.includes(role) ? value.roles.filter((item) => item !== role) : [...value.roles, role],
    });

  return (
    <div className="space-y-4">
      <fieldset>
        <legend className="mb-2 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("staffRoles")}</legend>
        <div className="flex flex-wrap gap-2">
          {invitable.map((role) => {
            const on = value.roles.includes(role);
            return (
              <button
                key={role}
                type="button"
                aria-pressed={on}
                onClick={() => toggle(role)}
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{
                  background: on ? "var(--primary)" : "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: on ? "var(--primary-contrast)" : "var(--text-soft)",
                }}
              >
                <RoleLabel role={role} />
              </button>
            );
          })}
        </div>
        {value.roles.length === 0 ? (
          <p className="mt-2 text-xs" style={{ color: "var(--muted)" }}>{t("chooseOneRole")}</p>
        ) : null}
      </fieldset>
      {showBranches ? (
        <BranchScopePicker
          locations={locations.data ?? []}
          value={scope}
          allowed={actorScope}
          legend={t("inviteBranches")}
          help={t("inviteBranchesHelp")}
          onChange={(next) => onChange({ ...value, scope: next })}
        />
      ) : null}
    </div>
  );
}

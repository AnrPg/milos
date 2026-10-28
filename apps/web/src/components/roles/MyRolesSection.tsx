"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";

import { updateMyRoles, type RoleName } from "@/api/roles";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { RoleChipsEditor } from "@/components/roles/RoleChipsEditor";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { selfAssignableRoles } from "@/lib/role-hierarchy";
import { membershipRoles } from "@/lib/role-navigation";

/**
 * Settings › «Οι ρόλοι μου» (ADR-219): someone adds or drops roles below
 * their top role in the selected box, e.g. an owner who also coaches. The
 * top role stays locked; members and athletes have nothing below them, so
 * the section is hidden for them.
 */
export function MyRolesSection() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const { membership } = useSelectedMembershipRole();
  const roles = membershipRoles(membership);
  const editable = selfAssignableRoles(roles);
  const mutation = useMutation({
    mutationFn: (next: RoleName[]) => updateMyRoles(token!, next),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["organization-memberships"] }),
  });

  if (!token || !membership || editable.length === 0) return null;

  return (
    <CollapsibleSection id="my-roles" title={i18n("myRolesTitle")} description={i18n("myRolesDescription")}>
      <RoleChipsEditor
        // A saved set becomes the new baseline and clears the draft.
        key={roles.join()}
        label={i18n("myRolesTitle")}
        current={roles}
        editable={editable}
        pending={mutation.isPending}
        error={mutation.isError ? localizeError(mutation.error, i18n) : null}
        onSave={(next) => mutation.mutate(next)}
      />
      <p className="mt-3 text-xs" style={{ color: "var(--dim)" }}>{i18n("myRolesHelp")}</p>
    </CollapsibleSection>
  );
}

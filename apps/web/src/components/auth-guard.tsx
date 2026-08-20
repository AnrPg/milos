"use client";


import {useUiTranslations} from "@/i18n/ui";
import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";

import { useSession } from "@/components/session-provider";
import { membershipWorkspaceHref } from "@/lib/organization-slug";
import { useSelectedMembershipRole } from "@/lib/membership-role";

type AuthGuardProps = {
  children: React.ReactNode;
  roles?: Array<"member" | "athlete" | "admin">;
  roleRedirects?: Partial<Record<"member" | "athlete" | "admin", string>>;
};

type AllowedRole = NonNullable<AuthGuardProps["roles"]>[number];
type SelectedMembership = ReturnType<typeof useSelectedMembershipRole>["membership"];
type RedirectRole = "member" | "athlete" | "admin";

function isAllowedRole(value: string): value is AllowedRole {
  return value === "member" || value === "athlete" || value === "admin";
}

export function resolveRoleRedirect(
  configuredRedirect: string | undefined,
  membership: SelectedMembership,
) {
  return configuredRedirect === "/admin" && membership
    ? membershipWorkspaceHref(membership)
    : configuredRedirect;
}

// Vendors (SaaS operators, `currentUser.vendor`) are exempt from
// roleRedirects: their tenant-membership role (if any) is irrelevant to
// where they land, since the platform console is their home regardless.
export function AuthGuard({ children, roles, roleRedirects }: AuthGuardProps) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const pathname = usePathname();
  const { status, currentUser } = useSession();
  const { isLoading: membershipRoleLoading, membership, role } = useSelectedMembershipRole();
  const accountRole = currentUser?.role;
  const redirectRole =
    membership || !isAllowedRole(accountRole ?? "") ? role : (accountRole as RedirectRole);
  const awaitingTenantAdminMembership =
    status === "authenticated" &&
    !currentUser?.vendor &&
    accountRole === "admin" &&
    roleRedirects?.admin === "/admin" &&
    !membership;

  useEffect(() => {
    if (status === "guest") {
      router.replace(`/login?next=${encodeURIComponent(pathname)}`);
      return;
    }

    if (status === "authenticated" && currentUser && !membershipRoleLoading) {
      if (!currentUser.vendor) {
        const roleKey = redirectRole;
        const configuredRedirect = roleRedirects?.[roleKey];
        const redirect = resolveRoleRedirect(configuredRedirect, membership);
        if (redirect) {
          router.replace(redirect);
          return;
        }
      }
      if (roles && (!isAllowedRole(redirectRole) || !roles.includes(redirectRole))) {
        router.replace("/");
      }
    }
  }, [
    currentUser,
    membership,
    membershipRoleLoading,
    pathname,
    redirectRole,
    roles,
    roleRedirects,
    router,
    status,
  ]);

  if (
    status === "loading" ||
    (status === "authenticated" && roles && membershipRoleLoading) ||
    awaitingTenantAdminMembership
  ) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[var(--bg)] px-6">
        <p className="text-sm font-medium uppercase tracking-[0.24em] text-black/45">
          {i18n("restoringSession5a59aa5")}
        </p>
      </main>
    );
  }

  if (status === "guest") return null;

  if (roles && currentUser && (!isAllowedRole(redirectRole) || !roles.includes(redirectRole))) {
    return null;
  }

  const roleKey = currentUser && !currentUser.vendor ? redirectRole : undefined;
  if (roleKey && roleRedirects?.[roleKey]) return null;

  return <>{children}</>;
}

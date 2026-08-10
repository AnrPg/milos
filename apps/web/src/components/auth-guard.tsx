"use client";


import {useUiTranslations} from "@/i18n/ui";
import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";

import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";

type AuthGuardProps = {
  children: React.ReactNode;
  roles?: Array<"member" | "athlete" | "admin">;
  roleRedirects?: Partial<Record<"member" | "athlete" | "admin", string>>;
};

type AllowedRole = NonNullable<AuthGuardProps["roles"]>[number];

function isAllowedRole(value: string): value is AllowedRole {
  return value === "member" || value === "athlete" || value === "admin";
}

// Vendors (SaaS operators, `currentUser.vendor`) are exempt from
// roleRedirects: their tenant-membership role (if any) is irrelevant to
// where they land, since the platform console is their home regardless.
export function AuthGuard({ children, roles, roleRedirects }: AuthGuardProps) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const pathname = usePathname();
  const { status, currentUser } = useSession();
  const { isLoading: membershipRoleLoading, role } = useSelectedMembershipRole();

  useEffect(() => {
    if (status === "guest") {
      router.replace(`/login?next=${encodeURIComponent(pathname)}`);
      return;
    }

    if (status === "authenticated" && currentUser && !membershipRoleLoading) {
      if (!currentUser.vendor) {
        const roleKey = role;
        const redirect = roleRedirects?.[roleKey];
        if (redirect) {
          router.replace(redirect);
          return;
        }
      }
      if (roles && (!isAllowedRole(role) || !roles.includes(role))) {
        router.replace("/");
      }
    }
  }, [currentUser, membershipRoleLoading, pathname, role, roles, roleRedirects, router, status]);

  if (status === "loading" || (status === "authenticated" && roles && membershipRoleLoading)) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[var(--bg)] px-6">
        <p className="text-sm font-medium uppercase tracking-[0.24em] text-black/45">
          {i18n("restoringSession5a59aa5")}
        </p>
      </main>
    );
  }

  if (status === "guest") return null;

  if (roles && currentUser && (!isAllowedRole(role) || !roles.includes(role))) {
    return null;
  }

  const roleKey = currentUser && !currentUser.vendor ? role : undefined;
  if (roleKey && roleRedirects?.[roleKey]) return null;

  return <>{children}</>;
}

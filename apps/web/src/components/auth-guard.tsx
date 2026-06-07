"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";

import { useSession } from "@/components/session-provider";

type AuthGuardProps = {
  children: React.ReactNode;
  roles?: Array<"member" | "athlete" | "admin">;
};

type AllowedRole = NonNullable<AuthGuardProps["roles"]>[number];

function isAllowedRole(value: string): value is AllowedRole {
  return value === "member" || value === "athlete" || value === "admin";
}

export function AuthGuard({ children, roles }: AuthGuardProps) {
  const router = useRouter();
  const pathname = usePathname();
  const { status, currentUser } = useSession();

  useEffect(() => {
    if (status === "guest") {
      router.replace(`/login?next=${encodeURIComponent(pathname)}`);
      return;
    }

    if (
      status === "authenticated" &&
      currentUser &&
      roles &&
      (!isAllowedRole(currentUser.role) || !roles.includes(currentUser.role))
    ) {
      router.replace("/");
    }
  }, [currentUser, pathname, roles, router, status]);

  if (status === "loading") {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#fffdf8] px-6">
        <p className="text-sm font-medium uppercase tracking-[0.24em] text-black/45">
          Restoring session...
        </p>
      </main>
    );
  }

  if (status === "guest") return null;

  if (roles && currentUser && (!isAllowedRole(currentUser.role) || !roles.includes(currentUser.role))) {
    return null;
  }

  return <>{children}</>;
}

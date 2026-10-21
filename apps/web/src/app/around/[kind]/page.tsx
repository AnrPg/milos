import { notFound } from "next/navigation";

import { AROUND_KINDS, type AroundKind } from "@/api/around";
import { AroundKindPage } from "@/components/around/AroundKindPage";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

/** «Δες όλα» for one Γύρω μου kind: events, boxes, clubs or posts. */
export default async function AroundKindRoute({ params }: { params: Promise<{ kind: string }> }) {
  const { kind } = await params;
  if (!(AROUND_KINDS as string[]).includes(kind)) notFound();
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <AroundKindPage kind={kind as AroundKind} />
    </AuthGuard>
  );
}

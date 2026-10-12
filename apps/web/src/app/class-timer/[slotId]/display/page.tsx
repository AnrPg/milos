"use client";

import { useParams } from "next/navigation";

import { AuthGuard } from "@/components/auth-guard";
import { ClassTimerDisplay } from "@/components/class-timer/ClassTimerDisplay";

export default function ClassTimerDisplayPage() {
  const params = useParams<{ slotId: string }>();
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <ClassTimerDisplay slotId={params.slotId} />
    </AuthGuard>
  );
}

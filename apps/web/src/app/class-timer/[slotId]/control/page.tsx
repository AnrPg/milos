"use client";

import { useParams } from "next/navigation";

import { AuthGuard } from "@/components/auth-guard";
import { ClassTimerControl } from "@/components/class-timer/ClassTimerControl";

export default function ClassTimerControlPage() {
  const params = useParams<{ slotId: string }>();
  return (
    <AuthGuard roles={["admin"]}>
      <ClassTimerControl slotId={params.slotId} />
    </AuthGuard>
  );
}

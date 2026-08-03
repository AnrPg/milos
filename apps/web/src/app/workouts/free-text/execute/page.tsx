"use client";

import { AuthGuard } from "@/components/auth-guard";
import { FreeTextExecutionMode } from "@/components/workouts/execution/FreeTextExecutionMode";

export default function FreeTextExecutePage() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <FreeTextExecutionMode />
    </AuthGuard>
  );
}

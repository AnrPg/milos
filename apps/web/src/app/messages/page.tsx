import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { MessagesPage } from "@/components/chat/inbox/MessagesPage";

export const dynamic = "force-dynamic";

/** Αρχική › ✈ Μηνύματα: the one inbox (ADR-196); `/me/activity/chats` redirects here. */
export default function MessagesRoute() {
  return (
    <AuthGuard>
      <Suspense>
        <MessagesPage />
      </Suspense>
    </AuthGuard>
  );
}

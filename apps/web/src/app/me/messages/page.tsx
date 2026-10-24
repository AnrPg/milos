import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { ConversationsPage } from "@/components/conversations/ConversationsPage";

export const dynamic = "force-dynamic";

// ADR-193 §3: person conversations belong to the account, so anyone signed
// in may open them, with or without a gym (no role filter).
export default function MessagesRoute() {
  return (
    <AuthGuard>
      <Suspense>
        <ConversationsPage />
      </Suspense>
    </AuthGuard>
  );
}

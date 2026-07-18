"use client";

import { useEffect, useState } from "react";

import { sharePR, type PRRecord } from "@/api/gamification";
import { InAppShareDialog } from "@/components/share-export/InAppShareDialog";
import { useSession } from "@/components/session-provider";
import { formatScore } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

export function PRShareModal({ pr, onClose }: { pr: PRRecord; onClose: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!tokens?.access_token) return;
    sharePR(tokens.access_token, pr.id)
      .then((response) => setMessage(response.message))
      .catch(() => setMessage(i18n("prShareFallback", {
        name: pr.name,
        score: formatScore(pr.current_score, undefined, pr.unit, i18n),
      })));
  }, [i18n, pr, tokens?.access_token]);

  return <InAppShareDialog message={message} onClose={onClose} title={pr.name} />;
}

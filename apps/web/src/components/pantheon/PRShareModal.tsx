"use client";

import { useEffect, useRef, useState } from "react";

import { createDirectThread, searchUsers, sendMessage } from "@/api/messaging";
import { sharePR, type PRRecord } from "@/api/gamification";
import { SemanticLabel } from "@/components/semantic-label";
import { ShareExportDialog } from "@/components/share-export/ShareExportDialog";
import { useShareExport } from "@/components/share-export/useShareExport";
import { useSession } from "@/components/session-provider";
import { formatScore } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { buildPRDocument } from "@/lib/document-export";

type UserResult = { id: string; nickname: string; role: string };

export function PRShareModal({ pr, onClose }: { pr: PRRecord; onClose: () => void }) {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const shareExport = useShareExport();
  const { tokens } = useSession();
  const [message, setMessage] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<UserResult[]>([]);
  const [selected, setSelected] = useState<UserResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!tokens?.access_token) return;
    sharePR(tokens.access_token, pr.id)
      .then((response) => setMessage(response.message))
      .catch(() => setMessage(i18n("prShareFallback", {
        name: pr.name,
        score: formatScore(pr.current_score, undefined, pr.unit, i18n),
      })));
  }, [i18n, pr, tokens?.access_token]);

  useEffect(() => () => {
    if (searchTimer.current) clearTimeout(searchTimer.current);
  }, []);

  function handleQueryChange(value: string) {
    setQuery(value);
    if (searchTimer.current) clearTimeout(searchTimer.current);
    if (!value.trim()) {
      setResults([]);
      return;
    }
    searchTimer.current = setTimeout(async () => {
      if (!tokens?.access_token) return;
      setSearching(true);
      try {
        const data = await searchUsers(tokens.access_token, value);
        setResults(data.users.filter((user) => !selected.some((candidate) => candidate.id === user.id)));
      } finally {
        setSearching(false);
      }
    }, 280);
  }

  function selectUser(user: UserResult) {
    setSelected((current) => [...current, user]);
    setResults((current) => current.filter((candidate) => candidate.id !== user.id));
    setQuery("");
  }

  async function handleSend() {
    if (!tokens?.access_token || !message || selected.length === 0) return;
    setSending(true);
    setError(null);
    try {
      await Promise.all(selected.map(async (user) => {
        const { thread } = await createDirectThread(tokens.access_token, user.id);
        await sendMessage(tokens.access_token, thread.id, message);
      }));
      setSent(true);
    } catch {
      setError(i18n("failedToSendToSomeRecipientsTryAgain89e1632"));
    } finally {
      setSending(false);
    }
  }

  const internalShare = (
    <section aria-label={i18n("sharePrf54c0df")}>
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
            💬 {i18n("sharePrf54c0df")}
          </p>
          <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{message}</p>
        </div>
      </div>

      {sent ? (
        <p className="mt-4 rounded-2xl px-4 py-3 text-center text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--success) 12%, transparent)", color: "var(--success)" }}>
          {i18n("sentToPeople", { count: selected.length })}
        </p>
      ) : (
        <div className="mt-4 space-y-3">
          {selected.length > 0 ? (
            <div className="flex flex-wrap gap-2">
              {selected.map((user) => (
                <button
                  key={user.id}
                  className="rounded-full px-3 py-1.5 text-xs font-semibold"
                  onClick={() => setSelected((current) => current.filter((candidate) => candidate.id !== user.id))}
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  type="button"
                >
                  {user.nickname} ✕
                </button>
              ))}
            </div>
          ) : null}

          <div className="relative">
            <input
              className="w-full rounded-2xl px-4 py-3 text-sm outline-none"
              onChange={(event) => handleQueryChange(event.target.value)}
              placeholder={i18n("searchPeopleToSendTocb4501a")}
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={query}
            />
            {searching ? <span className="absolute end-4 top-1/2 -translate-y-1/2" style={{ color: "var(--dim)" }}>…</span> : null}
          </div>

          {results.length > 0 ? (
            <div className="overflow-hidden rounded-2xl" style={{ border: "1px solid var(--border)" }}>
              {results.map((user, index) => (
                <button
                  key={user.id}
                  className="flex w-full items-center justify-between px-4 py-3 text-start text-sm"
                  onClick={() => selectUser(user)}
                  style={{ borderTop: index > 0 ? "1px solid var(--border)" : undefined, color: "var(--text)" }}
                  type="button"
                >
                  <span className="font-semibold">{user.nickname}</span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}><SemanticLabel value={user.role} /></span>
                </button>
              ))}
            </div>
          ) : null}

          {error ? <p className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{error}</p> : null}

          <button
            className="w-full rounded-2xl py-3 text-sm font-semibold disabled:opacity-40"
            disabled={selected.length === 0 || sending || !message}
            onClick={() => void handleSend()}
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            type="button"
          >
            {sending
              ? i18n("sendingcf76551")
              : selected.length === 0
                ? i18n("selectAtLeastOnePerson1e6c16e")
                : i18n("sendToPeople", { count: selected.length })}
          </button>
        </div>
      )}
    </section>
  );

  return (
    <ShareExportDialog
      copy={shareExport.copy}
      document={buildPRDocument(pr, shareExport.labels, uiLocale)}
      onClose={onClose}
      secondaryContent={internalShare}
    />
  );
}

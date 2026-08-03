"use client";

import { useId, useRef, useState } from "react";

import { createDirectThread, searchUsers, sendMessage } from "@/api/messaging";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import { useUiTranslations } from "@/i18n/ui";

type UserResult = { id: string; nickname: string; role: string };

export function InAppShareDialog({
  title,
  message,
  onClose,
}: {
  title: string;
  message: string | null;
  onClose: () => void;
}) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<UserResult[]>([]);
  const [selected, setSelected] = useState<UserResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const titleId = useId();
  const dialogRef = useModalFocusTrap<HTMLDivElement>(onClose);

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

  return (
    <div
      className="fixed inset-0 z-[80] flex items-end justify-center p-3 sm:items-center sm:p-6"
      onClick={(event) => { if (event.target === event.currentTarget) onClose(); }}
      role="presentation"
      style={{ background: "rgba(8, 12, 24, 0.72)", backdropFilter: "blur(8px)" }}
    >
      <div
        ref={dialogRef}
        aria-labelledby={titleId}
        aria-modal="true"
        className="max-h-[88vh] w-full max-w-lg overflow-y-auto rounded-[1.5rem] p-5 outline-none sm:p-6"
        role="dialog"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        tabIndex={-1}
      >
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>
              {i18n("shareInMilos")}
            </p>
            <h2 id={titleId} className="mt-1 truncate text-xl font-bold" style={{ color: "var(--text)" }}>{title}</h2>
          </div>
          <button
            aria-label={i18n("closebbfa773")}
            className="shrink-0 rounded-full px-3 py-1.5 text-xs font-semibold"
            onClick={onClose}
            style={{ background: "var(--border)", color: "var(--muted)" }}
            type="button"
          >
            {i18n("closebbfa773")}
          </button>
        </div>

        <p className="mt-4 whitespace-pre-wrap text-sm leading-6" style={{ color: "var(--muted)" }}>{message}</p>

        {sent ? (
          <p className="mt-5 rounded-xl px-4 py-3 text-center text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--success) 12%, transparent)", color: "var(--success)" }}>
            {i18n("sentToPeople", { count: selected.length })}
          </p>
        ) : (
          <div className="mt-5 space-y-3">
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
                    {user.nickname} ×
                  </button>
                ))}
              </div>
            ) : null}

            <div className="relative">
              <input
                className="w-full rounded-xl px-4 py-3 text-sm outline-none"
                onChange={(event) => handleQueryChange(event.target.value)}
                placeholder={i18n("searchPeopleToSendTocb4501a")}
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={query}
              />
              {searching ? <span className="absolute end-4 top-1/2 -translate-y-1/2" style={{ color: "var(--dim)" }}>…</span> : null}
            </div>

            {results.length > 0 ? (
              <div className="overflow-hidden rounded-xl" style={{ border: "1px solid var(--border)" }}>
                {results.map((user, index) => (
                  <button
                    key={user.id}
                    className="flex w-full items-center justify-between px-4 py-3 text-start text-sm"
                    onClick={() => {
                      setSelected((current) => [...current, user]);
                      setResults((current) => current.filter((candidate) => candidate.id !== user.id));
                      setQuery("");
                    }}
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
              className="w-full rounded-xl py-3 text-sm font-semibold disabled:opacity-40"
              disabled={selected.length === 0 || sending || !message}
              onClick={() => void handleSend()}
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
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
      </div>
    </div>
  );
}

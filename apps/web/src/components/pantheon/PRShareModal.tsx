"use client";

import { useEffect, useRef, useState } from "react";
import { createDirectThread, searchUsers, sendMessage } from "@/api/messaging";
import { sharePR, type PRRecord } from "@/api/gamification";
import { useSession } from "@/components/session-provider";

type UserResult = { id: string; nickname: string; role: string };

export function PRShareModal({ pr, onClose }: { pr: PRRecord; onClose: () => void }) {
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
    const handleKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [onClose]);

  useEffect(() => {
    if (!tokens?.access_token) return;
    sharePR(tokens.access_token, pr.id)
      .then((r) => setMessage(r.message))
      .catch(() => setMessage(`🏆 ${pr.name}: ${pr.current_score} ${pr.unit}`));
  }, [tokens?.access_token, pr]);

  function handleQueryChange(q: string) {
    setQuery(q);
    if (searchTimer.current) clearTimeout(searchTimer.current);
    if (!q.trim()) { setResults([]); return; }
    searchTimer.current = setTimeout(async () => {
      if (!tokens?.access_token) return;
      setSearching(true);
      try {
        const data = await searchUsers(tokens.access_token, q);
        setResults(data.users.filter((u) => !selected.some((s) => s.id === u.id)));
      } finally {
        setSearching(false);
      }
    }, 280);
  }

  function toggleUser(user: UserResult) {
    setSelected((prev) =>
      prev.some((u) => u.id === user.id)
        ? prev.filter((u) => u.id !== user.id)
        : [...prev, user],
    );
    setResults((prev) => prev.filter((u) => u.id !== user.id));
    setQuery("");
  }

  async function handleSend() {
    if (!tokens?.access_token || !message || selected.length === 0) return;
    setSending(true);
    setError(null);
    try {
      await Promise.all(
        selected.map(async (user) => {
          const { thread } = await createDirectThread(tokens.access_token, user.id);
          await sendMessage(tokens.access_token, thread.id, message);
        }),
      );
      setSent(true);
    } catch {
      setError("Failed to send to some recipients. Try again.");
    } finally {
      setSending(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center p-4 sm:items-center"
      style={{ background: "rgba(0,0,0,0.5)" }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        className="w-full max-w-md rounded-[2rem] p-6 space-y-4"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
              Share PR
            </p>
            <h2 className="mt-1 text-lg font-semibold" style={{ color: "var(--text)" }}>{pr.name}</h2>
          </div>
          <button type="button" onClick={onClose} className="text-xl shrink-0" style={{ color: "var(--dim)" }}>✕</button>
        </div>

        {/* Message preview */}
        {message && (
          <div
            className="rounded-xl px-4 py-3 text-sm"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {message}
          </div>
        )}

        {sent ? (
          <div className="space-y-3">
            <p className="text-sm font-semibold text-center py-4" style={{ color: "var(--success, var(--primary))" }}>
              🎉 Sent to {selected.length} {selected.length === 1 ? "person" : "people"}!
            </p>
            <button
              type="button"
              onClick={onClose}
              className="w-full rounded-2xl py-3 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              Done
            </button>
          </div>
        ) : (
          <>
            {/* Selected users chips */}
            {selected.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {selected.map((u) => (
                  <button
                    key={u.id}
                    type="button"
                    onClick={() => setSelected((prev) => prev.filter((s) => s.id !== u.id))}
                    className="flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold"
                    style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  >
                    {u.nickname} ✕
                  </button>
                ))}
              </div>
            )}

            {/* Search input */}
            <div className="relative">
              <input
                className="w-full rounded-2xl px-4 py-3 text-sm outline-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                }}
                placeholder="Search people to send to…"
                value={query}
                onChange={(e) => handleQueryChange(e.target.value)}
                autoFocus
              />
              {searching && (
                <span
                  className="absolute right-4 top-1/2 -translate-y-1/2 text-xs"
                  style={{ color: "var(--dim)" }}
                >
                  …
                </span>
              )}
            </div>

            {/* Search results */}
            {results.length > 0 && (
              <div
                className="rounded-2xl overflow-hidden"
                style={{ border: "1px solid var(--border)" }}
              >
                {results.map((u, i) => (
                  <button
                    key={u.id}
                    type="button"
                    onClick={() => toggleUser(u)}
                    className="flex w-full items-center justify-between px-4 py-3 text-left text-sm transition-colors hover:bg-[var(--panel-muted)]"
                    style={{
                      borderTop: i > 0 ? "1px solid var(--border)" : undefined,
                      color: "var(--text)",
                    }}
                  >
                    <span className="font-semibold">{u.nickname}</span>
                    <span className="text-xs capitalize" style={{ color: "var(--dim)" }}>{u.role}</span>
                  </button>
                ))}
              </div>
            )}

            {error && (
              <p className="text-xs font-semibold" style={{ color: "var(--danger, var(--primary))" }}>
                {error}
              </p>
            )}

            <button
              type="button"
              onClick={() => void handleSend()}
              disabled={selected.length === 0 || sending || !message}
              className="w-full rounded-2xl py-3.5 text-sm font-semibold disabled:opacity-40"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {sending
                ? "Sending…"
                : selected.length === 0
                  ? "Select at least one person"
                  : `Send to ${selected.length} ${selected.length === 1 ? "person" : "people"}`}
            </button>
          </>
        )}
      </div>
    </div>
  );
}

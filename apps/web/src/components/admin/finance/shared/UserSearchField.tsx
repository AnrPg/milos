"use client";

import { useEffect, useRef, useState } from "react";
import { fetchAdminSearch, type FinanceRecord } from "@/api/finance";

interface Props {
  label: string;
  value: string;
  prefillUser?: FinanceRecord | null;
  token: string;
  onChange: (userId: string, user: FinanceRecord | null) => void;
  excludeUserId?: string;
  locked?: boolean;
}

function field(record: FinanceRecord | null | undefined, key: string): string {
  const v = record?.[key];
  if (v === null || v === undefined) return "";
  return String(v);
}

export function UserSearchField({ label, value, prefillUser, token, onChange, excludeUserId, locked }: Props) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<FinanceRecord[]>([]);
  const [selectedUser, setSelectedUser] = useState<FinanceRecord | null>(null);
  const [loading, setLoading] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Prefill without API call
  useEffect(() => {
    if (prefillUser && !value) {
      queueMicrotask(() => {
        setSelectedUser(prefillUser);
        onChange(field(prefillUser, "id"), prefillUser);
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [prefillUser]);

  // Clear selection if value externally reset to empty
  useEffect(() => {
    if (!value) {
      queueMicrotask(() => {
        setSelectedUser(null);
        setQuery("");
      });
    }
  }, [value]);

  useEffect(() => {
    if (query.length < 2) {
      queueMicrotask(() => setResults([]));
      return;
    }

    if (debounceRef.current) clearTimeout(debounceRef.current);

    debounceRef.current = setTimeout(async () => {
      setLoading(true);
      try {
        const data = await fetchAdminSearch(token, query, "all");
        const users = (data.users ?? [])
          .filter((u) => {
            const role = field(u, "identity_role");
            return role === "member" || role === "athlete";
          })
          .filter((u) => !excludeUserId || field(u, "id") !== excludeUserId)
          .slice(0, 20);
        setResults(users);
      } finally {
        setLoading(false);
      }
    }, 150);

    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [query, token, excludeUserId]);

  function select(user: FinanceRecord) {
    setSelectedUser(user);
    setQuery("");
    setResults([]);
    onChange(field(user, "id"), user);
  }

  function clear() {
    setSelectedUser(null);
    setQuery("");
    setResults([]);
    onChange("", null);
  }

  return (
    <div className="space-y-1">
      <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {label}
      </label>

      {selectedUser ? (
        <div
          className="flex items-center gap-2 rounded-xl px-3 py-2 w-full"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)" }}
        >
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {field(selectedUser, "nickname")}
          </span>
          <span
            className="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider"
            style={{
              background:
                field(selectedUser, "identity_role") === "athlete"
                  ? "color-mix(in srgb, var(--primary) 12%, transparent)"
                  : "color-mix(in srgb, var(--muted) 12%, transparent)",
              color:
                field(selectedUser, "identity_role") === "athlete" ? "var(--primary)" : "var(--muted)",
            }}
          >
            {field(selectedUser, "identity_role")}
          </span>
          {!locked && (
            <button
              type="button"
              onClick={clear}
              className="ml-auto text-xs hover:opacity-70 transition-opacity"
              style={{ color: "var(--dim)" }}
            >
              ✕
            </button>
          )}
        </div>
      ) : locked ? (
        <div
          className="rounded-xl px-3 py-2 w-full"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--dim)" }}
        >
          <span className="text-sm italic">Not selected</span>
        </div>
      ) : (
        <div className="relative">
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search by nickname…"
            className="w-full rounded-xl px-3 py-2 text-sm"
            style={{
              background: "var(--panel-muted)",
              border: "1px solid var(--border-strong)",
              color: "var(--text)",
            }}
          />

          {(results.length > 0 || loading) && (
            <div
              className="absolute left-0 top-full z-50 mt-1 w-full rounded-xl overflow-hidden shadow-xl"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)" }}
            >
              {loading ? (
                <p className="px-3 py-2 text-xs" style={{ color: "var(--dim)" }}>
                  Searching…
                </p>
              ) : (
                results.map((u) => (
                  <button
                    key={field(u, "id")}
                    type="button"
                    onClick={() => select(u)}
                    className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-[var(--border)] transition-colors"
                  >
                    <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                      {field(u, "nickname")}
                    </span>
                    <span className="text-xs" style={{ color: "var(--dim)" }}>
                      {field(u, "identity_role")}
                    </span>
                  </button>
                ))
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

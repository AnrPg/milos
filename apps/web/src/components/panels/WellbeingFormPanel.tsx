"use client";

import { useState } from "react";
import { useMutation } from "@tanstack/react-query";

import { reportInjury } from "@/api/wellbeing";
import { useSession } from "@/components/session-provider";

export function WellbeingFormPanel({ onClose }: { onClose: () => void }) {
  const { tokens } = useSession();
  const [bodyArea, setBodyArea] = useState("");
  const [severity, setSeverity] = useState("mild");
  const [limitations, setLimitations] = useState("");
  const [submitted, setSubmitted] = useState(false);

  const reportMutation = useMutation({
    mutationFn: async () =>
      reportInjury(tokens!.access_token, {
        body_area: bodyArea,
        severity,
        training_limitations: limitations,
      }),
    onSuccess: () => {
      setBodyArea("");
      setLimitations("");
      setSubmitted(true);
    },
  });

  return (
    <div
      className="fixed inset-y-0 right-0 z-50 flex flex-col"
      style={{ width: "380px", background: "var(--panel)", borderLeft: "1px solid var(--border)" }}
    >
      <div
        className="flex items-center justify-between px-5 py-4 border-b"
        style={{ borderColor: "var(--border)" }}
      >
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
            Training Readiness
          </p>
          <p className="text-sm mt-0.5" style={{ color: "var(--muted)" }}>
            Report discomfort or limitations
          </p>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="text-lg leading-none"
          style={{ color: "var(--dim)" }}
        >
          ✕
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-5">
        {submitted ? (
          <div className="py-8 text-center">
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
              Submitted. Thank you.
            </p>
            <button
              type="button"
              className="mt-4 text-sm"
              style={{ color: "var(--primary)" }}
              onClick={() => setSubmitted(false)}
            >
              Report another
            </button>
          </div>
        ) : (
          <form
            className="space-y-4"
            onSubmit={(e) => {
              e.preventDefault();
              reportMutation.mutate();
            }}
          >
            <div>
              <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--muted)" }}>
                Body area
              </label>
              <input
                className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                }}
                placeholder="e.g. right shoulder"
                required
                value={bodyArea}
                onChange={(e) => setBodyArea(e.target.value)}
              />
            </div>

            <div>
              <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--muted)" }}>
                Severity
              </label>
              <select
                className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                }}
                value={severity}
                onChange={(e) => setSeverity(e.target.value)}
              >
                <option value="mild">Mild — can train with care</option>
                <option value="moderate">Moderate — limited training</option>
                <option value="severe">Severe — cannot train</option>
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold mb-1.5" style={{ color: "var(--muted)" }}>
                Training limitations (optional)
              </label>
              <textarea
                className="w-full rounded-xl px-3 py-2.5 text-sm outline-none resize-none"
                style={{
                  background: "var(--panel-muted)",
                  border: "1px solid var(--border)",
                  color: "var(--text)",
                  minHeight: "80px",
                }}
                placeholder="Describe what movements hurt or are not possible…"
                value={limitations}
                onChange={(e) => setLimitations(e.target.value)}
              />
            </div>

            {reportMutation.error instanceof Error && (
              <p className="text-xs font-semibold" style={{ color: "var(--danger)" }}>
                {reportMutation.error.message}
              </p>
            )}

            <button
              type="submit"
              disabled={reportMutation.isPending || !bodyArea.trim()}
              className="w-full rounded-xl py-2.5 text-sm font-semibold"
              style={{
                background: "var(--primary)",
                color: "var(--primary-contrast)",
                opacity: reportMutation.isPending || !bodyArea.trim() ? 0.5 : 1,
              }}
            >
              {reportMutation.isPending ? "Reporting…" : "Submit report"}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}

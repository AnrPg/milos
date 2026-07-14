"use client";

import { ReviewForm } from "@/components/my-reviews";

export function ReviewFormPanel({ onClose }: { onClose: () => void }) {
  return (
    <div
      className="fixed inset-y-0 right-0 z-50 flex flex-col"
      style={{ width: "440px", background: "var(--panel)", borderLeft: "1px solid var(--border)" }}
    >
      <div
        className="flex items-center justify-between px-5 py-4 border-b"
        style={{ borderColor: "var(--border)" }}
      >
        <div>
          <p
            className="text-xs font-bold uppercase tracking-[0.22em]"
            style={{ color: "var(--primary)" }}
          >
            Leave a Review
          </p>
          <p className="text-sm mt-0.5" style={{ color: "var(--muted)" }}>
            Share your feedback with your coach
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
        <ReviewForm />
      </div>
    </div>
  );
}

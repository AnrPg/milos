"use client";


import {useUiTranslations} from "@/i18n/ui";
import { ReviewForm } from "@/components/my-reviews";

export function ReviewFormPanel({ onClose }: { onClose: () => void }) {
  const i18n = useUiTranslations();
  return (
    <div
      className="fixed inset-y-0 end-0 z-50 flex flex-col"
      style={{ width: "440px", background: "var(--panel)", borderInlineStart: "1px solid var(--border)" }}
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
            {i18n("leaveAReview5e65b65")}
          </p>
          <p className="text-sm mt-0.5" style={{ color: "var(--muted)" }}>
            {i18n("shareYourFeedbackWithYourCoacha24d2a8")}
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

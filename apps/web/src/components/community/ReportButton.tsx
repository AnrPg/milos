"use client";

/**
 * «Αναφορά» as ANR asked for it (board 12): a subtle line-icon flag, low
 * contrast until hovered or focused, still a real button with a label and a
 * visible focus ring. It opens the M4 report sheet.
 */
export function ReportButton({
  label,
  onClick,
  tone = "subtle",
  className = "",
}: {
  label: string;
  onClick: () => void;
  tone?: "subtle" | "overlay";
  className?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      aria-haspopup="dialog"
      className={[
        "flex h-10 w-10 shrink-0 items-center justify-center rounded-full opacity-55 transition-opacity hover:opacity-100 focus-visible:opacity-100 focus-visible:outline-2 focus-visible:outline-offset-2",
        className,
      ].join(" ")}
      style={{
        color: tone === "overlay" ? "#fff" : "var(--dim)",
        outlineColor: tone === "overlay" ? "#fff" : "var(--primary)",
      }}
      data-testid="report-button"
    >
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M5 21V4" />
        <path d="M5 4h11l-2 4 2 4H5" />
      </svg>
    </button>
  );
}

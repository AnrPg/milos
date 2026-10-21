/**
 * The Palee "arms up" mark (docs/brand/BRAND.md): a round head between two
 * raised arms drawn as one thick stroke. Arms follow the text colour and the
 * head the primary colour, so the mark adapts to the active theme.
 */
export function PaleeMark({ className, title }: { className?: string; title?: string }) {
  return (
    <svg
      viewBox="20 20 160 160"
      className={className}
      role={title ? "img" : undefined}
      aria-hidden={title ? undefined : true}
      aria-label={title}
    >
      <path
        d="M40 52 Q46 150 100 150 Q154 150 160 52"
        fill="none"
        stroke="var(--text)"
        strokeWidth="26"
        strokeLinecap="round"
      />
      <circle cx="100" cy="88" r="24" fill="var(--primary)" />
    </svg>
  );
}

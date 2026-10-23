/**
 * ADR-187: a display name is free and not unique, so wherever people are
 * picked or searched the unique @handle sits under it to tell them apart.
 */
export function PersonName({
  name,
  handle,
  inline = false,
  className = "",
}: {
  name: string;
  handle?: string | null;
  /** Name and @handle on one line (chips, compact rows). */
  inline?: boolean;
  className?: string;
}) {
  const showHandle = Boolean(handle) && handle !== name;

  if (inline) {
    return (
      <span className={`min-w-0 truncate ${className}`}>
        <span className="font-semibold" style={{ color: "inherit" }}>{name}</span>
        {showHandle ? (
          <span className="ms-1.5 text-xs font-normal" style={{ color: "var(--dim)" }} dir="ltr">
            @{handle}
          </span>
        ) : null}
      </span>
    );
  }

  return (
    <span className={`flex min-w-0 flex-col ${className}`}>
      <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{name}</span>
      {showHandle ? (
        <span className="truncate text-xs" style={{ color: "var(--dim)" }} dir="ltr">
          @{handle}
        </span>
      ) : null}
    </span>
  );
}

"use client";

type ViewModeSelectorProps<T extends string | number> = {
  value: T;
  options: Array<{ value: T; label: string; accessibleLabel: string }>;
  onChange: (value: T) => void;
};

export function ViewModeSelector<T extends string | number>({
  value,
  options,
  onChange,
}: ViewModeSelectorProps<T>) {
  return (
    <div
      aria-label="Calendar view"
      className="flex rounded-full p-0.5"
      role="group"
      style={{ background: "var(--border)" }}
    >
      {options.map((option) => (
        <button
          aria-label={option.accessibleLabel}
          aria-pressed={value === option.value}
          className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
          key={option.value}
          onClick={() => onChange(option.value)}
          style={
            value === option.value
              ? { background: "var(--text)", color: "var(--bg)" }
              : { color: "var(--dim)" }
          }
          type="button"
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

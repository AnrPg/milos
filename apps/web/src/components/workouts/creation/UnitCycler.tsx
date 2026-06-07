"use client";

type UnitCyclerProps<T extends string> = {
  options: readonly T[];
  value: T;
  onChange: (next: T) => void;
  labels?: Partial<Record<T, string>>;
};

export function UnitCycler<T extends string>({ options, value, onChange, labels }: UnitCyclerProps<T>) {
  function cycle() {
    const index = options.indexOf(value);
    onChange(options[(index + 1) % options.length]);
  }

  return (
    <button
      type="button"
      onClick={cycle}
      className="cursor-pointer select-none text-sm font-medium transition-colors"
      style={{ color: "var(--muted)" }}
      title={`Click to cycle: ${options.map((option) => labels?.[option] ?? option).join(" -> ")}`}
    >
      {labels?.[value] ?? value}
    </button>
  );
}

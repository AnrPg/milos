"use client";



import {useUiTranslations} from "@/i18n/ui";
type UnitCyclerProps<T extends string> = {
  options: readonly T[];
  value: T;
  onChange: (next: T) => void;
  labels?: Partial<Record<T, string>>;
};

export function UnitCycler<T extends string>({ options, value, onChange, labels }: UnitCyclerProps<T>) {
  const i18n = useUiTranslations();
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
      title={i18n("clickToCyclee521647") + (options.map((option) => labels?.[option] ?? option).join(" -> "))}
    >
      {labels?.[value] ?? value}
    </button>
  );
}

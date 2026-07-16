"use client";




import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";

export type ComboboxOption = {
  value: string;
  label: string;
  sublabel?: string;
};

export function Combobox({
  value,
  placeholder,
  options,
  onSearch,
  onChange,
  nullable = false,
  loading = false,
}: {
  value: string;
  placeholder?: string;
  options: ComboboxOption[];
  onSearch: (query: string) => void;
  onChange: (value: string) => void;
  nullable?: boolean;
  loading?: boolean;
}) {
  const i18n = useUiTranslations();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const selectedOption = options.find((o) => o.value === value);

  useEffect(() => {
    if (!open) return;
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      onSearch(query);
    }, 150);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [query, open, onSearch]);

  function handleOpen() {
    setOpen(true);
    setQuery("");
    onSearch("");
  }

  function handleBlur() {
    setTimeout(() => setOpen(false), 150);
  }

  function handleSelect(option: ComboboxOption) {
    onChange(option.value);
    setOpen(false);
    setQuery("");
  }

  function handleClear() {
    onChange("");
    setOpen(false);
    setQuery("");
  }

  return (
    <div className="relative">
      {open ? (
        <input
          autoFocus
          className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
          style={{ background: "var(--panel)", border: "1px solid var(--primary)", color: "var(--text)" }}
          placeholder={i18n("searchf54fbca")}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onBlur={handleBlur}
        />
      ) : (
        <button
          className="w-full rounded-[0.9rem] px-3 py-2 text-left text-sm"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: selectedOption ? "var(--text)" : "var(--dim)" }}
          onClick={handleOpen}
          type="button"
        >
          {selectedOption ? selectedOption.label : (placeholder ?? i18n("select349ac8f"))}
        </button>
      )}

      {open ? (
        <div
          className="absolute left-0 top-full z-30 mt-1 w-full rounded-[1rem] py-1 shadow-xl"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", maxHeight: "14rem", overflowY: "auto" }}
        >
          {loading ? (
            <p className="px-4 py-3 text-sm" style={{ color: "var(--dim)" }}>{i18n("searching1a6a5ba")}</p>
          ) : options.length === 0 ? (
            <p className="px-4 py-3 text-sm" style={{ color: "var(--dim)" }}>{i18n("noResults0035403")}</p>
          ) : (
            options.map((option) => (
              <button
                key={option.value}
                className="flex w-full flex-col px-4 py-2 text-left transition-colors hover:opacity-80"
                style={{ color: option.value === value ? "var(--primary)" : "var(--text)" }}
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => handleSelect(option)}
                type="button"
              >
                <span className="text-sm font-semibold">{option.label}</span>
                {option.sublabel ? (
                  <span className="text-xs" style={{ color: "var(--dim)" }}>{option.sublabel}</span>
                ) : null}
              </button>
            ))
          )}
          {nullable && value ? (
            <button
              className="w-full border-t px-4 py-2 text-left text-sm font-semibold"
              style={{ borderColor: "var(--border)", color: "var(--primary-strong)" }}
              onMouseDown={(e) => e.preventDefault()}
              onClick={handleClear}
              type="button"
            >
              {i18n("clearSelection247fd63")}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

"use client";

import { useEffect, useState } from "react";

type Props = {
  value: number | null;
  onChange: (seconds: number | null) => void;
};

export function TimeInput({ value, onChange }: Props) {
  const [minuteText, setMinuteText] = useState("");
  const [secondText, setSecondText] = useState("");

  useEffect(() => {
    const total = value ?? 0;
    const mins = Math.floor(total / 60);
    const secs = total % 60;
    const frame = window.requestAnimationFrame(() => {
      setMinuteText(mins > 0 ? String(mins) : "");
      setSecondText(secs > 0 ? String(secs) : "");
    });

    return () => window.cancelAnimationFrame(frame);
  }, [value]);

  function emit(nextMinuteText: string, nextSecondText: string) {
    const hasMinutes = nextMinuteText.trim() !== "";
    const hasSeconds = nextSecondText.trim() !== "";

    if (!hasMinutes && !hasSeconds) {
      onChange(null);
      return;
    }

    const mins = Number.parseInt(nextMinuteText, 10);
    const secs = Number.parseInt(nextSecondText, 10);
    const normalizedMinutes = Number.isNaN(mins) ? 0 : Math.max(0, mins);
    const normalizedSeconds = Number.isNaN(secs) ? 0 : Math.min(59, Math.max(0, secs));

    onChange((normalizedMinutes * 60) + normalizedSeconds);
  }

  const inputClass = "w-10 rounded-lg bg-transparent px-1 py-1 text-center text-sm outline-none";
  const inputStyle = {
    background: "var(--bg)",
    border: "1px solid var(--dim)",
    color: "var(--text)",
  };

  return (
    <div className="flex items-center gap-1">
      <input
        type="number"
        value={minuteText}
        placeholder="0"
        onChange={(e) => {
          const nextMinuteText = e.target.value;
          setMinuteText(nextMinuteText);
          emit(nextMinuteText, secondText);
        }}
        className={inputClass}
        style={inputStyle}
        min={0}
      />
      <span className="text-xs" style={{ color: "var(--muted)" }}>m</span>
      <input
        type="number"
        value={secondText}
        placeholder="0"
        onChange={(e) => {
          const rawSecondText = e.target.value;
          const parsedSeconds = Number.parseInt(rawSecondText, 10);
          const nextSecondText = Number.isNaN(parsedSeconds)
            ? rawSecondText
            : String(Math.min(59, Math.max(0, parsedSeconds)));

          setSecondText(nextSecondText);
          emit(minuteText, nextSecondText);
        }}
        className={inputClass}
        style={inputStyle}
        min={0}
        max={59}
      />
      <span className="text-xs" style={{ color: "var(--muted)" }}>s</span>
    </div>
  );
}

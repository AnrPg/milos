"use client";

import type { FieldView } from "./model";
import s from "./grid.module.css";

type Props = {
  /** Grid field key (`r:<row>:dose`, `c:<row>:<col>:l`…), used for focus and keyboard moves. */
  fieldKey: string;
  testId?: string;
  value: string;
  view: FieldView;
  ariaLabel: string;
  /** Error text for screen readers and the tooltip; the hint line shows it too. */
  errorText?: string;
  /** Translated unit suffix (the view's token run through the translator). */
  suffix?: string;
  onChange: (value: string) => void;
};

/**
 * ADR-270 value field: an input as wide as its content with its unit right
 * next to the value. A computed value (from `+5`, `60→80`, or one inherited)
 * is drawn inside the same field while it is not focused, `65` with a tiny
 * `+5` badge, never on an extra line. Errors only colour the field red; the
 * words go to the grid's hint line.
 */
export function ValueField({ fieldKey, testId, value, view, ariaLabel, errorText, suffix, onChange }: Props) {
  const shown = Boolean(view.display);
  return (
    <span className={s.vf} data-bad={view.error ? "" : undefined} data-disp={shown ? "" : undefined} data-testid={testId ? `${testId}-field` : undefined}>
      <input
        className={s.vi}
        data-key={fieldKey}
        data-testid={testId}
        value={value}
        placeholder={view.placeholder}
        aria-label={ariaLabel}
        aria-invalid={view.error ? true : undefined}
        title={errorText || undefined}
        autoComplete="off"
        spellCheck={false}
        size={Math.max(2, value.length || view.placeholder.length)}
        onChange={(event) => onChange(event.target.value)}
      />
      {suffix ? (
        <span className={s.vs} aria-hidden="true">
          {suffix}
        </span>
      ) : null}
      {shown ? (
        <span className={s.vd} aria-hidden="true" data-testid={testId ? `${testId}-display` : undefined}>
          <b>{view.display}</b>
          {view.badge ? <small>{view.badge}</small> : null}
        </span>
      ) : null}
    </span>
  );
}

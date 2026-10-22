import type { CSSProperties } from "react";

/**
 * Spark, the electric green (docs/brand/THEME.md › Brand roles): energy for
 * what is alive now and for creating something new. Always a fill with dark
 * text, never text on the page, and never the screen's main action (Dojo).
 */

/** "+ New …" and "+ Add …" chips: starting something new. */
export const SPARK_CREATE_STYLE: CSSProperties = {
  background: "var(--spark)",
  color: "var(--spark-contrast)",
  border: "1px solid var(--spark)",
};

/** "Active" and "Live" status pills. */
export const SPARK_ACTIVE_STYLE: CSSProperties = {
  background: "var(--spark)",
  color: "var(--spark-contrast)",
};

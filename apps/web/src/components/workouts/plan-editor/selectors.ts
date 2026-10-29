/**
 * DOM selectors of the structured WOD editor's keyboard handling (the shell
 * marks its fields with `data-k`, the grid with `data-key`, both with the
 * store's focus keys; the open section carries `data-sec`).
 */
export const SEL = {
  /** Every field a mutation can ask to focus. */
  focusKeys: "[data-k], [data-key]",
  /** The stops of ↑ ↓ between closed cards and the open section. */
  cardStops: "[data-k^='card:'], [data-sec]",
  controls: "input, button",
  /** The wizard step fields, in Enter order. */
  stepFields: "[data-k^='p:'], [data-k^='score:'], [data-k^='snote:'], [data-k^='lnote:']",
  section: (id: string) => `[data-sec="${id}"]`,
} as const;

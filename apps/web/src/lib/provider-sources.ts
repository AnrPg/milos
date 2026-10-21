import type { EntrySource, FormerProvider, MyProviders, Provider } from "@/api/providers";
import { SERIES_TOKENS, tokenVar } from "@/lib/theme";

/**
 * Where an entry came from (ADR-162, board 17 Q3): a provider (gym or
 * independent coach, «(πρώην)» once the membership ended), freeform or a
 * device. These helpers turn the API's `EntrySource` into the token the
 * filters take, a stable colour and the decision whether to show a label.
 */

/** The filter token for a source: the provider's id, `freeform` or `device`. */
export function sourceToken(source: Pick<EntrySource, "kind" | "organization_id">): string {
  if (source.kind === "organization" && source.organization_id) return source.organization_id;
  return source.kind === "device" ? "device" : "freeform";
}

// The theme's data-series colours: each provider gets one by its id, so it
// keeps it across screens (gym brand colours do not tint the app).
const PALETTE = SERIES_TOKENS.map(tokenVar);
export const FREEFORM_COLOR = tokenVar("seriesNeutral");
export const DEVICE_COLOR = tokenVar("series6");
export const FORMER_COLOR = tokenVar("dim");

function hash(text: string) {
  let value = 0;
  for (let index = 0; index < text.length; index += 1) value = (value * 31 + text.charCodeAt(index)) >>> 0;
  return value;
}

export function paletteColor(id: string) {
  return PALETTE[hash(id) % PALETTE.length];
}

/** A provider's series colour (stable by id; Palee wears one theme for every gym). */
export function providerColor(provider: { organization_id: string }) {
  return paletteColor(provider.organization_id);
}

export type SourceDirectory = {
  /** Active providers by organization id. */
  active: Map<string, Provider>;
  former: Map<string, FormerProvider>;
  /** More than one provider ever: labels tell them apart. */
  multiple: boolean;
};

export function sourceDirectory(data: MyProviders | null | undefined): SourceDirectory {
  const active = new Map((data?.providers ?? []).map((provider) => [provider.organization_id, provider]));
  const former = new Map((data?.former ?? []).map((provider) => [provider.organization_id, provider]));
  return { active, former, multiple: active.size + former.size > 1 };
}

export function sourceColor(source: EntrySource, directory: SourceDirectory) {
  if (source.kind === "device") return DEVICE_COLOR;
  if (source.kind === "freeform") return FREEFORM_COLOR;
  if (source.former) return FORMER_COLOR;
  const id = source.organization_id ?? "";
  const provider = directory.active.get(id);
  return provider ? providerColor(provider) : paletteColor(id);
}

/**
 * Whether an entry carries a source label: always for freeform and device
 * entries and for a provider you left; for a provider's entries only when
 * there is more than one provider to tell apart.
 */
export function showsSource(source: EntrySource | null | undefined, directory: SourceDirectory) {
  if (!source) return false;
  if (source.kind !== "organization" || source.former) return true;
  return directory.multiple;
}

/** Filter options for Πηγή: active providers, former ones, then freeform and device. */
export function sourceOptions(
  directory: SourceDirectory,
  labels: { freeform: string; device: string; former: (name: string) => string },
  opts: { device?: boolean } = {},
) {
  return [
    ...[...directory.active.values()].map((provider) => ({ value: provider.organization_id, label: provider.name })),
    ...[...directory.former.values()].map((provider) => ({
      value: provider.organization_id,
      label: labels.former(provider.name),
    })),
    { value: "freeform", label: labels.freeform },
    ...(opts.device === false ? [] : [{ value: "device", label: labels.device }]),
  ];
}

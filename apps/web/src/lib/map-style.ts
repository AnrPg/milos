// Street maps (Πρόγραμμα location picker, later Γύρω μου). The style is a
// MapLibre style URL; OpenFreeMap needs no key. Self-hosters point
// NEXT_PUBLIC_MAP_STYLE_URL at their own tiles.
const DEFAULT_MAP_STYLE_URL = "https://tiles.openfreemap.org/styles/liberty";

type MapEnv = Record<string, string | undefined>;

// Spelled out so Next inlines them into client bundles.
const buildEnv: MapEnv = {
  NEXT_PUBLIC_MAP_STYLE_URL: process.env.NEXT_PUBLIC_MAP_STYLE_URL,
  NEXT_PUBLIC_MAP_ORIGINS: process.env.NEXT_PUBLIC_MAP_ORIGINS,
};

export function mapStyleUrl(env: MapEnv = buildEnv) {
  return env.NEXT_PUBLIC_MAP_STYLE_URL || DEFAULT_MAP_STYLE_URL;
}

/** Origins the map loads its style, tiles, fonts and sprites from (for the CSP). */
export function configuredMapOrigins(env: MapEnv = buildEnv) {
  const extra = (env.NEXT_PUBLIC_MAP_ORIGINS ?? "").split(/[\s,]+/).filter(Boolean);
  try {
    return [new URL(mapStyleUrl(env)).origin, ...extra].join(" ");
  } catch {
    return extra.join(" ");
  }
}

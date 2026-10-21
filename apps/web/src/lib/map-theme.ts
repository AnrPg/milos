import type { LayerSpecification, Map as MapLibreMap } from "maplibre-gl";

import { readToken, type ThemeTokens } from "@/lib/theme";

/**
 * Street maps wear the theme (docs/brand/THEME.md › Maps): whatever vector
 * style the tiles come with, land, water, parks, buildings, roads, borders
 * and labels are repainted from the theme's map tokens, and again whenever
 * the member switches between light and dark.
 */

type Paint = { property: string; token: keyof ThemeTokens };

const WATER = /water|ocean|sea|lake|river|canal/;
const GREEN = /park|wood|forest|grass|green|garden|cemetery|pitch|golf|nature|scrub|wetland/;
const BUILDING = /building/;
const BOUNDARY = /boundary|admin/;
const CASING = /casing|outline/;
const MAJOR_ROAD = /motorway|trunk|primary|major/;
const ROAD = /road|highway|street|path|track|transport|bridge|tunnel|rail|aeroway|ferry/;

/** The theme paint for one style layer, or none for layers the theme leaves alone. */
export function mapLayerPaint(layer: Pick<LayerSpecification, "id" | "type">): Paint[] {
  const id = layer.id.toLowerCase();
  switch (layer.type) {
    case "background":
      return [{ property: "background-color", token: "mapLand" }];
    case "fill":
      if (WATER.test(id)) return [{ property: "fill-color", token: "mapWater" }];
      if (BUILDING.test(id)) {
        return [
          { property: "fill-color", token: "mapBuilding" },
          { property: "fill-outline-color", token: "mapRoadCasing" },
        ];
      }
      if (GREEN.test(id)) return [{ property: "fill-color", token: "mapPark" }];
      return [{ property: "fill-color", token: "mapLand" }];
    case "fill-extrusion":
      return [{ property: "fill-extrusion-color", token: "mapBuilding" }];
    case "line":
      if (WATER.test(id)) return [{ property: "line-color", token: "mapWater" }];
      if (BOUNDARY.test(id)) return [{ property: "line-color", token: "mapBoundary" }];
      if (CASING.test(id)) return [{ property: "line-color", token: "mapRoadCasing" }];
      if (MAJOR_ROAD.test(id)) return [{ property: "line-color", token: "mapRoadMajor" }];
      if (ROAD.test(id)) return [{ property: "line-color", token: "mapRoad" }];
      return [{ property: "line-color", token: "mapBoundary" }];
    case "symbol":
      return [
        { property: "text-color", token: "mapLabel" },
        { property: "text-halo-color", token: "mapLabelHalo" },
      ];
    default:
      return [];
  }
}

function paintMap(map: MapLibreMap) {
  for (const layer of map.getStyle()?.layers ?? []) {
    for (const { property, token } of mapLayerPaint(layer)) {
      try {
        map.setPaintProperty(layer.id, property as Parameters<MapLibreMap["setPaintProperty"]>[1], readToken(token));
      } catch {
        // A layer that cannot take this paint keeps the style's own.
      }
    }
  }
}

/** Repaints the map from the theme now, on every style load and on each theme switch. */
export function followMapTheme(map: MapLibreMap): () => void {
  const repaint = () => {
    if (map.isStyleLoaded()) paintMap(map);
  };
  map.on("style.load", () => paintMap(map));
  repaint();
  const observer = new MutationObserver(repaint);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  return () => observer.disconnect();
}

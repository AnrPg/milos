import { describe, expect, it } from "vitest";

import { mapLayerPaint } from "./map-theme";

describe("map theme", () => {
  it("paints each kind of map layer from its theme token", () => {
    expect(mapLayerPaint({ id: "background", type: "background" })).toEqual([{ property: "background-color", token: "mapLand" }]);
    expect(mapLayerPaint({ id: "water", type: "fill" })[0]?.token).toBe("mapWater");
    expect(mapLayerPaint({ id: "park", type: "fill" })[0]?.token).toBe("mapPark");
    expect(mapLayerPaint({ id: "building", type: "fill" }).map((paint) => paint.token)).toEqual(["mapBuilding", "mapRoadCasing"]);
    expect(mapLayerPaint({ id: "highway_motorway_casing", type: "line" })[0]?.token).toBe("mapRoadCasing");
    expect(mapLayerPaint({ id: "highway_primary", type: "line" })[0]?.token).toBe("mapRoadMajor");
    expect(mapLayerPaint({ id: "highway_minor", type: "line" })[0]?.token).toBe("mapRoad");
    expect(mapLayerPaint({ id: "boundary_country", type: "line" })[0]?.token).toBe("mapBoundary");
    expect(mapLayerPaint({ id: "place_city", type: "symbol" }).map((paint) => paint.token)).toEqual(["mapLabel", "mapLabelHalo"]);
    expect(mapLayerPaint({ id: "hillshade", type: "hillshade" })).toEqual([]);
  });
});
